# Idea

A local web app for a five-person team to run their standup asynchronously. Each person posts a short daily update (done, doing next, blocked), and the board shows everyone's latest update side by side with the past week below. Anyone can mark an update as a blocker, and blockers float to the top with a clear count. It opens already filled with a week of realistic updates from five named people, so the team sees how it feels straight away.

## Constraints

- Stack: one command to run, SQLite or a JSON file for storage
- Must run offline on a laptop; no accounts, no cloud services, no auth
- The five team members are fixed in the seed data; posting picks a name from a list
