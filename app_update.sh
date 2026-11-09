#!/bin/bash
# Change the "Please update" settings. See tools/app_update.js for options.
cd "$(dirname "$0")"
NODE_PATH=functions/node_modules node tools/app_update.js "$@"
