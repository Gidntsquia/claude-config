#!/bin/bash
# A process of the user's own, which no tool may kill. Writes its pid to $1; the test's teardown kills it.
echo $$ > "$1"
exec sleep 300
