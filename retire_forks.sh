#!/bin/bash
# Script to retire unused forks with no personal commits

echo "Deleting nifi fork..."
gh repo delete NickJLange/nifi --yes

echo "Deleting homebridge forks..."
gh repo delete NickJLange/homebridge-mqttthing --yes
gh repo delete NickJLange/homebridge-wyze-connected-home --yes
gh repo delete NickJLange/homebridge-tasmota --yes
gh repo delete NickJLange/homebridge.container --yes

echo "Done."
