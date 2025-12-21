#!/bin/bash
test_str="3 packets transmitted, 1 received, 66.6667% packet loss, time 2002ms"
echo "Input: $test_str"
echo "Current Grep:"
echo "$test_str" | grep -oP '\d+(?=% packet loss)'

echo "---"
echo "Proposed Awk solution:"
echo "$test_str" | grep -oP '\d+(\.\d+)?(?=% packet loss)' | awk -F. '{print $1}'
