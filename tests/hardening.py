"""Regression tests for release controls. No live Claude/GitHub calls."""
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import agent_hook
import brief
import budget
import budget_hook
import policy
import quality
import runner
import runtime


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="qs-release-")
        self.root = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.root), "QS_ROLE": "lead"})
        self.env.start()
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.root)], check=True)
        (self.root / "README.md").write_text("hello\n")
        subprocess.run(["git", "add", "README.md"], cwd=self.root, check=True)
        subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "initial"], cwd=self.root, check=True)
        self.b = {"mission": {"goal": "test", "deliverables": ["README.md"]},
                  "success_criteria": [{"kind": "file", "path": "README.md"}],
                  "quality": {"profile": "docs"}, "maintenance": False,
                  "budgets": {"tokens": 10000000, "cost_usd": 1000, "wall_clock_min": 60, "steps": 1000},
                  "permissions": {"irreversible": {"default": "skip-and-record", "allow": []}}}
        runtime.atomic(runtime.state() / "brief.json", self.b)
        runtime.atomic(runtime.state() / "started_at", dt.datetime.now(dt.timezone.utc).isoformat())
        self.config = {"schema": 3, "brief": self.b, "hashes": runner.hashes(self.root), "deadline": time.time() + 3600}
        runtime.atomic(runtime.state() / "controller.json", self.config)

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def event(self, command=None, tool="Bash", path=None, agent=None, aid=None):
        e = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input":
             {"command": command} if tool == "Bash" else {"file_path": path}, "cwd": str(self.root)}
        if agent:
            e.update(agent_type=agent, agent_id=aid or "agent-1")
        return e

    def deny(self, event):
        with self.assertRaises(policy.Denied):
            policy.check(event)

    def test_pr_merge_variants(self):
        for cmd in ('gh pr merge 123 --squash', 'gh --repo org/repo pr merge 123', 'gh api /repos/x/pulls/1/merge -X PUT'):
            with self.subTest(command=cmd):
                self.deny(self.event(cmd))

    def test_main_and_force_refspecs(self):
        for cmd in ('git push origin --delete refs/heads/main', 'git -C . push origin HEAD:refs/heads/master',
                    'git push origin +HEAD:mission/test', 'git push --force-with-lease origin mission/test'):
            with self.subTest(command=cmd):
                self.deny(self.event(cmd))

    def test_agent_cannot_publish(self):
        self.b['permissions']['irreversible']['default'] = 'allow'
        for cmd in ('git push origin mission/test', 'gh pr create --title test', 'npm publish'):
            self.deny(self.event(cmd))

    def test_operator_permissions(self):
        with self.assertRaises(policy.Denied):
            policy.authorize('git push origin mission/test', self.b)
        self.b['permissions']['irreversible']['allow'] = ['git push origin mission/*']
        policy.authorize('git push origin mission/test', self.b)
        with self.assertRaises(policy.Denied):
            policy.authorize('gh pr create --base main', self.b)

    def test_shell_production_writes(self):
        for cmd in ('echo x > "vercel.json"', 'cp README.md infra/main.tf', 'cat README.md | tee netlify.toml'):
            self.deny(self.event(cmd))

    def test_secret_paths(self):
        for path in ('.env', 'src/.env.production', str(self.root / '.env.local')):
            self.deny(self.event(tool='Read', path=path))
        policy.check(self.event(tool='Read', path='.env.example'))

    def test_harness_integrity(self):
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/guard.py').write_text('original')
        self.deny(self.event(tool='Write', path='scripts/guard.py'))
        self.deny(self.event('echo x > scripts/guard.py'))
        self.deny(self.event('cp README.md scripts/guard.py'))

    def test_controller_artifacts_protected(self):
        for path in ('docs/RUN_STATE', 'docs/COMPLETION.json', 'BRIEF.yaml', '.claude/state/controller.json'):
            self.deny(self.event(tool='Write', path=path))
        policy.check(self.event(tool='Write', path='docs/RESULT.json'))

    def test_shell_ambiguity(self):
        for cmd in ('bash -c "git push origin main"', 'python -c "print(1)"', 'echo $(pwd)', 'echo `pwd`', 'cat <<EOF', 'ls &'):
            self.deny(self.event(cmd))

    def test_powershell_and_connectors(self):
        self.deny(self.event(tool='PowerShell', path='x'))
        self.deny({'tool_name': 'mcp__github__create_pull_request', 'tool_input': {}})

    def test_path_escape(self):
        self.deny(self.event(tool='Write', path='../outside.txt'))
        self.deny(self.event('git -C .. status'))

    def test_symlink_escape(self):
        with tempfile.TemporaryDirectory() as other:
            try:
                (self.root / 'link').symlink_to(other, target_is_directory=True)
            except OSError:
                self.skipTest('symlinks unavailable without Windows developer mode')
            self.deny(self.event(tool='Write', path='link/file.txt'))

    def register(self, slug='work', sid='s001', aid='agent-1'):
        with runtime.transaction() as db:
            runtime.put(db, 'step:' + sid, {'id': sid, 'slug': slug, 'legs': []})
        e = self.event('python scripts/ledger.py step-bind ' + sid, agent='worker', aid=aid)
        policy.check(e)
        return e

    def test_agent_bind_required(self):
        self.deny(self.event('git status', agent='worker'))
        self.deny(self.event(tool='Write', path='src/file.py', agent='worker'))

    def test_bind_is_unique(self):
        self.register()
        self.deny(self.event('python scripts/ledger.py step-bind s001', agent='worker', aid='other'))

    def test_worker_owns_files(self):
        self.register()
        runtime.atomic(self.root / 'docs/ledgers/task.json', {'plan': [{'slug':'work','owns':['src/file.py']}]})
        policy.check(self.event(tool='Write', path='.claude/worktrees/work/src/file.py', agent='worker'))
        self.deny(self.event(tool='Write', path='.claude/worktrees/work/src/other.py', agent='worker'))
        self.deny(self.event(tool='Write', path='src/file.py', agent='worker'))

    def test_worker_git_target(self):
        self.register()
        policy.check(self.event('git -C .claude/worktrees/work status', agent='worker'))
        self.deny(self.event('git -C . status', agent='worker'))

    def test_parallel_bindings(self):
        self.register('a', 's001', 'a')
        self.register('b', 's002', 'b')
        self.assertEqual(policy.bound_step(self.event('ls', agent='worker', aid='a'))['slug'], 'a')
        self.assertEqual(policy.bound_step(self.event('ls', agent='worker', aid='b'))['slug'], 'b')

    def test_researcher_scope(self):
        self.register('research')
        policy.check(self.event(tool='Write', path='work/_untrusted/research.md', agent='researcher'))
        self.deny(self.event(tool='Write', path='src/file.py', agent='researcher'))
        self.deny(self.event('ls', agent='researcher'))

    def test_read_only_roles(self):
        self.register()
        for role in ('reviewer', 'security'):
            self.deny(self.event(tool='Write', path='docs/report.md', agent=role))

    def test_maintenance_worktree_only(self):
        self.register()
        runtime.atomic(self.root / 'docs/ledgers/task.json', {'plan':[{'slug':'work','owns':['scripts/guard.py']}]})
        self.deny(self.event(tool='Write', path='.claude/worktrees/work/scripts/guard.py', agent='worker'))
        self.config['brief']['maintenance'] = True
        runtime.atomic(runtime.state() / 'controller.json', self.config)
        policy.check(self.event(tool='Write', path='.claude/worktrees/work/scripts/guard.py', agent='worker'))
        self.deny(self.event(tool='Write', path='scripts/guard.py'))

    def test_gate_missing_node_scripts(self):
        (self.root / 'package.json').write_text('{"name":"empty","version":"1.0.0"}')
        (self.root / 'node_modules').mkdir()
        data = quality.gate(self.root, {'quality': {'profile':'code'}})
        self.assertFalse(data['pass'])
        self.assertEqual(len(data['failures']), 3)

    def test_explicit_skip_reasons(self):
        data = quality.gate(self.root, {'quality': {k:{'skip':'operator supplied'} for k in ('lint','test','build')}})
        self.assertTrue(data['pass'])

    def test_docs_rejects_code(self):
        (self.root / 'source.py').write_text('print(1)')
        self.assertFalse(quality.gate(self.root, self.b)['pass'])

    def test_gate_failing_command(self):
        b = {'quality':{k:'exit 0' for k in ('lint','test','build')}}
        b['quality']['test'] = 'exit 7'
        self.assertIn('test failed', quality.gate(self.root, b)['failures'])

    def test_full_transcript_after_20mb(self):
        p = self.root / 'usage.jsonl'
        p.write_bytes((json.dumps({'padding':'x' * (1024*1024)})+'\n').encode()*21 +
                     (json.dumps({'message':{'id':'large','usage':{'input_tokens':2000000}}})+'\n').encode())
        self.assertEqual(budget.usage(str(p))[0], 2000000)
        self.assertEqual(budget.incremental_usage(str(p))[0], 2000000)

    def test_incremental_partial_and_duplicates(self):
        p = self.root / 'usage.jsonl'
        line = json.dumps({'message':{'id':'one','usage':{'input_tokens':3}}})
        p.write_text(line)
        self.assertEqual(budget.incremental_usage(str(p))[0], 0)
        p.write_text(line+'\n'+line+'\n')
        self.assertEqual(budget.incremental_usage(str(p))[0], 3)
        self.assertEqual(budget.incremental_usage(str(p))[0], 3)
        p.write_text(json.dumps({'message':{'id':'two','usage':{'input_tokens':7}}})+'\n')
        self.assertEqual(budget.incremental_usage(str(p))[0], 7)

    def test_budget_attempts_exactly_once(self):
        tp = self.root / 'usage.jsonl';tp.write_text('{}\n')
        e = self.event('git status');e.update(transcript_path=str(tp),tool_use_id='unique',session_id='session')
        self.assertEqual(budget_hook.handle(e), 0)
        self.assertEqual(budget_hook.handle(e), 0)
        e['hook_event_name'] = 'PostToolUseFailure'
        self.assertEqual(budget_hook.handle(e), 0)
        self.assertEqual((runtime.state() / 'steps').read_text().strip(), '1')

    def test_parallel_counter(self):
        def count(_):
            with runtime.transaction() as db:
                return runtime.increment(db, 'counter')
        with ThreadPoolExecutor(max_workers=8) as pool:
            vals = list(pool.map(count, range(40)))
        self.assertEqual(sorted(vals), list(range(1,41)))

    def test_missing_accounting_denies_mutation(self):
        self.assertEqual(budget_hook.handle(self.event('git status')), 2)

    def test_final_report_escape_not_allowed(self):
        self.b['budgets']['steps'] = 1
        runtime.atomic(runtime.state() / 'controller.json', self.config)
        runtime.atomic(runtime.state() / 'steps','1')
        self.assertEqual(budget_hook.handle(self.event(tool='Write', path='mydocs/REPORT.md')), 2)

    def test_final_writes_remain_possible(self):
        self.b['budgets']['steps'] = 1
        runtime.atomic(runtime.state() / 'controller.json', self.config)
        runtime.atomic(runtime.state() / 'steps','1')
        self.assertEqual(budget_hook.handle(self.event(tool='Write', path='docs/RESULT.json')), 0)

    def test_launcher_no_result_not_success(self):
        self.assertEqual(runner.finalize(self.root,self.config),5)
        self.assertTrue((self.root/'docs/REPORT.md').exists())

    def test_launcher_policy_tamper_halts(self):
        (self.root/'BRIEF.yaml').write_text('changed')
        self.assertEqual(runner.finalize(self.root,self.config),4)

    def test_partial_submission_never_publishes(self):
        runtime.atomic(self.root/'docs/RESULT.json',{'state':'DONE_PARTIAL','reason':'limit'})
        with patch.object(runner,'publish') as pub:
            self.assertEqual(runner.finalize(self.root,self.config),3)
            pub.assert_not_called()

    def test_deadline_before_verification(self):
        runtime.atomic(self.root/'docs/RESULT.json',{'state':'READY'})
        self.config['deadline'] = time.time()-1
        self.assertEqual(runner.finalize(self.root,self.config),3)

    def test_security_must_be_actual_agent_response(self):
        runtime.atomic(self.root/'docs/RESULT.json',{'state':'READY','security':'PASS'})
        with patch.object(runner,'publish') as pub:
            self.assertEqual(runner.finalize(self.root,self.config),3)
            pub.assert_not_called()

    def test_security_hook_records_head(self):
        agent_hook.handle({'hook_event_name':'SubagentStop','agent_type':'security','agent_id':'security-1','last_assistant_message':'PASS\nchecked diff'})
        with runtime.transaction() as db:
            record = runtime.get(db,'security')
        self.assertEqual(record['verdict'],'PASS')
        self.assertEqual(record['head'],quality.git(self.root,'rev-parse','HEAD'))

    def test_judge_deferred_not_done(self):
        self.b['success_criteria'] = [{'kind':'judge','rubric':'check'}]
        self.assertEqual(runner.verify_criteria(self.root,self.b,self.config)['failed'],1)

    def test_judge_requires_evidence(self):
        self.b['success_criteria'] = [{'kind':'judge','rubric':'check'}]
        runtime.atomic(self.root/'docs/ledgers/criteria.json',{'results':[{'kind':'judge','status':'pass','detail':'PASS'}]})
        self.assertEqual(runner.verify_criteria(self.root,self.b,self.config)['failed'],1)

    def test_deliverable_path_escape(self):
        self.b['mission']['deliverables'] = ['../missing.md']
        runtime.atomic(self.root/'docs/RESULT.json',{'state':'READY'})
        self.assertEqual(runner.finalize(self.root,self.config),3)

    def test_quality_schema(self):
        raw=dict(self.b,ambiguity_policy='choose-default-and-record')
        for val in ({'profile':'wrong'},{'test':{'skip':''}},{'test':7}):
            with self.assertRaises(brief.BriefError):
                brief.validate_structure(dict(raw,quality=val))

    def test_process_deadline(self):
        args=[sys.executable,'-c','import time; time.sleep(20)']
        rc,reason=runner.launch(args,self.root,self.root/'output.json',time.time()+.3,dict(os.environ))
        self.assertEqual(reason,'wall-clock deadline exceeded')
        self.assertNotEqual(rc,0)


if __name__ == '__main__':
    unittest.main(verbosity=1)
