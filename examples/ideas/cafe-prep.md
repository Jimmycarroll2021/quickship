# Idea

A command-line tool for small cafe owners that reads the daily sales CSV their point-of-sale system exports, works out which menu items sold out and at what time, and suggests tomorrow's prep quantities so they stop running out of the bestsellers by noon and stop binning unsold pastries at close. Today they eyeball last week's numbers on paper.

## Constraints

- Stack: Python 3.12, managed with uv
- Must run offline on a laptop; no accounts, no cloud services
- Input: one CSV per day in a folder; output: a printed prep list plus a CSV

## Contract

- The cafe is open 07:00 to 15:00.
- The input folder holds two files per day. `sales-YYYY-MM-DD.csv` is the till export, with header `timestamp,item,quantity`, one row per sale line, ISO timestamps in time order. `prep-YYYY-MM-DD.csv` is what was baked that morning, with header `item,prepped`. Any other file in the folder is ignored.
- An item sold out on a day when its sales reach the prepped count. The sell-out time is the timestamp of the sale that reached it.
- `bash prep.sh <folder> <out.csv>` prints tomorrow's prep list, naming each item that sold out and the time it usually ran out, and writes `<out.csv>` with header `item,quantity`: one row per item, whole numbers. Like `demo.sh`, it installs whatever it needs on first run.
