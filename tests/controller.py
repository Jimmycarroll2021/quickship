"""Launcher/preflight/publishing compatibility cases with simulated providers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import unittest
from unittest.mock import patch
import hardening

import preflight
import quality
import runner
import runtime


class ControllerTests(unittest.TestCase):
    setUp = hardening.ReleaseTests.setUp
    tearDown = hardening.ReleaseTests.tearDown

    def setup_launcher(self):
        source = Path(__file__).resolve().parents[1]
        shutil.copytree(source/'scripts', self.root/'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(source/'.claude/agents', self.root/'.claude/agents')
        runtime.atomic(self.root/'.claude/settings.json', {'permissions':{'allow':['Bash(git status *)']}, 'hooks':{}})
        self.config['hashes'] = runner.hashes(self.root)
        runtime.atomic(runtime.state()/'controller.json', self.config)
        self.check = {'errors':[], 'brief':self.b, 'auth':{'authMethod':'claude.ai'}}

    def call_main(self, lead_rc=0, payload=None, reason=None, finalize_rc=0):
        self.setup_launcher()
        calls=[]
        def launch(args, root, output, deadline, env):
            calls.append(args)
            runtime.atomic(output, payload if payload is not None else {'session_id':'session-123','is_error':False})
            return lead_rc, reason
        original = runner.run
        def commands(args, root, **kwargs):
            if len(args)>1 and args[1] in ('scripts/brief.py','scripts/ledger.py'):
                return 'current'
            return original(args,root,**kwargs)
        with patch.object(preflight,'inspect',return_value=self.check), patch.object(runner,'launch',side_effect=launch), \
                patch.object(runner,'run',side_effect=commands), patch.object(runner,'finalize',return_value=finalize_rc), \
                patch.dict(os.environ,{'QS_OVERSEER':'0','QS_SLEEP':'0'}):
            code=runner.main()
        return code,calls

    def test_fresh_start_passes_flags_and_saves_session(self):
        code,calls=self.call_main()
        self.assertEqual(code,0)
        for flag in ('-p','--permission-prompts','--allowedTools','--strict-mcp-config','--settings','--agents','--max-turns'):
            self.assertIn(flag,calls[0])
        self.assertNotIn('--bare',calls[0])
        self.assertNotIn('--max-budget-usd',calls[0])
        self.assertEqual((runtime.state()/'session_id').read_text().strip(),'session-123')

    def test_resume_uses_saved_session(self):
        runtime.atomic(runtime.state()/'session_id','previous-session\n')
        code,calls=self.call_main()
        self.assertEqual(code,0)
        self.assertEqual(calls[0][calls[0].index('--resume')+1],'previous-session')

    def test_resume_restores_only_controller_report_changes(self):
        report=self.root/'docs/REPORT.md'
        runtime.atomic(report,'# Lead report\n\nEvidence remains.\n')
        runner.finish(self.root,'ERROR','publication unavailable')
        runner.restore_controller_report(self.root)
        self.assertEqual(report.read_text(),'# Lead report\n\nEvidence remains.\n')
        runner.finish(self.root,'SAFE_STOP','interrupted')
        report.write_text(report.read_text()+'User addition.\n')
        runner.restore_controller_report(self.root)
        self.assertTrue(report.read_text().endswith('User addition.\n'))

    def test_done_returns_without_model(self):
        runtime.atomic(self.root/'docs/COMPLETION.json',{'schema':3,'state':'DONE'})
        code,calls=self.call_main()
        self.assertEqual((code,len(calls)),(0,0))

    def test_halt_returns_without_model(self):
        runtime.atomic(self.root/'docs/COMPLETION.json',{'schema':3,'state':'HALT'})
        code,calls=self.call_main()
        self.assertEqual((code,len(calls)),(4,0))

    def test_restart_limit_produces_report(self):
        with runtime.transaction() as db:
            runtime.put(db,'launches',5)
        code,calls=self.call_main()
        self.assertEqual((code,len(calls)),(3,0))
        self.assertIn('restart limit',(self.root/'docs/REPORT.md').read_text())

    def test_expired_resume_does_not_launch(self):
        self.config['deadline']=time.time()-1
        runtime.atomic(runtime.state()/'controller.json',self.config)
        code,calls=self.call_main()
        self.assertEqual((code,len(calls)),(3,0))

    def test_cancel_and_deadline_states(self):
        code,_=self.call_main(reason='cancelled')
        self.assertEqual(code,3)
        self.assertEqual(runtime.load(self.root/'docs/RUN_STATE')['state'],'SAFE_STOP')

    def test_model_error_does_not_finalize_successfully(self):
        code,_=self.call_main(lead_rc=1,payload={'session_id':'session-123','is_error':True})
        self.assertEqual(code,3)
        self.assertEqual(runtime.load(self.root/'docs/RUN_STATE')['state'],'SAFE_STOP')

    def test_killed_run_recovers_transcript_session(self):
        transcript=runtime.state()/'session-abcd.jsonl';transcript.write_text('{}\n')
        runtime.atomic(runtime.state()/'transcript_path',str(transcript))
        code,_=self.call_main(lead_rc=137,payload={})
        self.assertEqual(code,3)
        self.assertEqual((runtime.state()/'session_id').read_text().strip(),'session-abcd')

    def test_missing_saved_transcript_stops_before_model(self):
        runtime.atomic(runtime.state()/'transcript_path',str(self.root/'missing.jsonl'))
        code,calls=self.call_main()
        self.assertEqual((code,len(calls)),(3,0))

    def test_exhausted_steps_stop_before_model(self):
        runtime.atomic(runtime.state()/'steps','1000')
        code,calls=self.call_main()
        self.assertEqual((code,len(calls)),(3,0))

    def test_process_success_propagates_verification_failure(self):
        code,_=self.call_main(finalize_rc=5)
        self.assertEqual(code,5)

    def test_preflight_failure_no_model(self):
        self.setup_launcher()
        self.check['errors']=['brief missing']
        with patch.object(preflight,'inspect',return_value=self.check), patch.object(runner,'launch') as launch:
            self.assertEqual(runner.main(),2)
            launch.assert_not_called()

    def test_changed_brief_refused_without_model(self):
        self.setup_launcher()
        self.check['brief']=dict(self.b,maintenance=True)
        with patch.object(preflight,'inspect',return_value=self.check), patch.object(runner,'run',return_value='current'), patch.object(runner,'launch') as launch:
            self.assertEqual(runner.main(),2)
            launch.assert_not_called()

    def test_auth_diagnostics_redact_identifiers(self):
        self.setup_launcher()
        (self.root/'BRIEF.yaml').write_text('mission: {}')
        def command(args,root):
            if args[0]==quality.bash():return 'GNU bash, version 5.2'
            if args==['claude','auth','status']:return json.dumps({'loggedIn':True,'authMethod':'claude.ai','subscriptionType':'max','email':'private@example.invalid'})
            if args==['claude','--version']:return '2.1.288 (Claude Code)'
            if args==['claude','--help']:return '--permission-prompts --strict-mcp-config --allowedTools --max-budget-usd'
            return ''
        with patch.object(preflight,'command',side_effect=command), patch.object(shutil,'which',return_value='/tool'):
            info=preflight.inspect(self.root)
        self.assertNotIn('private@example.invalid',json.dumps(info))
        self.assertEqual(info['auth']['subscriptionType'],'max')

    def test_incompatible_old_runtime_preserved(self):
        self.setup_launcher()
        (runtime.state()/'controller.json').unlink()
        runtime.atomic(runtime.state()/'session_id','old')
        # Minimal valid YAML with optional quality overrides in block form.
        (self.root/'BRIEF.yaml').write_text('''mission:
  goal: test
  deliverables:
    - README.md
success_criteria:
  - {kind: file, path: README.md}
budgets:
  tokens: 100
  cost_usd: 1
  wall_clock_min: 10
  steps: 10
permissions:
  irreversible:
    default: skip-and-record
ambiguity_policy: choose-default-and-record
quality:
  profile: docs
''')
        with patch.object(preflight,'command',side_effect=ValueError('fixture')):
            info=preflight.inspect(self.root)
        self.assertTrue(any('v0.2 active state' in x for x in info['errors']))
        self.assertEqual((runtime.state()/'session_id').read_text(),'old')

    def test_publication_reconciles_existing_pr(self):
        self.b['permissions']['irreversible']['allow']=['git push origin mission/*','gh pr create*']
        pub={'url':'https://github.com/example/test/pull/1','headRefOid':'abc','headRefName':'mission/test','baseRefName':'main'}
        mutations=[]
        def provider(args,root,**kw):
            if args[:3]==['gh','repo','view']:return 'main'
            if args[:2]==['git','ls-remote']:return 'abc\trefs/heads/mission/test'
            if args[:3]==['gh','pr','list']:return json.dumps([pub])
            mutations.append(args);return ''
        with patch.object(runner,'run',side_effect=provider):
            first=runner.publish(self.root,self.config,'mission/test','abc')
            second=runner.publish(self.root,self.config,'mission/test','abc')
        self.assertEqual(first,second)
        self.assertFalse(mutations)

    def test_pr_mismatch_refuses_done(self):
        self.b['permissions']['irreversible']['default']='allow'
        pub={'url':'https://github.com/example/test/pull/1','headRefOid':'wrong','headRefName':'mission/test','baseRefName':'main'}
        def provider(args,root,**kw):
            if args[:3]==['gh','repo','view']:return 'main'
            if args[:2]==['git','ls-remote']:return 'abc\trefs/heads/mission/test'
            if args[:3]==['gh','pr','list']:return json.dumps([pub])
            return ''
        with patch.object(runner,'run',side_effect=provider), self.assertRaises(ValueError):
            runner.publish(self.root,self.config,'mission/test','abc')

    def test_publication_never_main(self):
        self.b['permissions']['irreversible']['default']='allow'
        with patch.object(runner,'run',return_value='main'),self.assertRaises(ValueError):
            runner.publish(self.root,self.config,'main','abc')


if __name__=='__main__':
    unittest.main()
