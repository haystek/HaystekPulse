#!/bin/bash
cd "$(dirname "$0")"
NODE_PATH=functions/node_modules node tools/dummy_chat.js "$@"
