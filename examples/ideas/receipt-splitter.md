# Idea

A web app for splitting a restaurant bill. Paste the text of a receipt, and it turns each line into an item with a price. Tap people against each line (shared items split evenly between whoever is tapped), and the app shows who owes what, including their share of tax and tip. It opens with three seeded receipts (a pizza night, a brunch and a team lunch) so the first screen is never empty.

## Constraints

- Stack: one command to run, a JSON file or SQLite for storage
- Must run offline on a laptop; no accounts, no cloud services, no OCR or image upload
- Money is handled in whole pence or cents, never floats; totals must always add up exactly
