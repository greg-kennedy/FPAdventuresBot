# FPAdventuresBot
Twitter bot for posting screenshots.

## Overview
This repository contains the source code for the Twitter bot [@FPAdventuresBot](https://twitter.com/FPAdventuresBot).  The bot posts a random screenshot from first-person adventure games, once every 6 hours.

In addition to the code for the bot, there is a [`tools/`](./tools/) subfolder.  Within `tools/` are any custom tools I've written to extract data from specific games.

## Usage
`main.pl` is the master script.  It reads in `config.pl` for API info to connect to Twitter, and selects a screenshot at random from the `data/` subfolder.  It will make a single post, if enough time has passed since the last status update.

Of course you shouldn't run it manually.  Edit your crontab file and add a line like the following:

    0 4,10,16,22 * * * cd /home/userid/FPAdventuresBot && ./main.pl >/dev/null 2>&1

This line will kick the bot off at 4 AM, 10 AM, 4 PM and 10 PM each day.
