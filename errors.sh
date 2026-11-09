#!/bin/bash
# Show the latest error notes from the app. See tools/errors.js.
cd "$(dirname "$0")"
NODE_PATH=functions/node_modules node tools/errors.js "$@"
