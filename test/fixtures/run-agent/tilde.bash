# Test inputs that carry a literal tilde: what a person types after /run-agent, for run-agent itself to expand.
# They live here because the lint in test/run refuses a tilde in test files. HOME is the test's temp home.
TILDE_FILES='worker ~/files'
TILDE_TWO='worker ~/a ~/b'
TILDE_FILES_WANT="{\"dir\":\"$TEST_HOME/files\",\"dir_state\":\"exists\",\"dir_typed\":\"~/files\",\"command\":\"claude --agent worker \\\".\\\" --name \\\"worker: files (sonnet)\\\"\",\"run\":\"S worker . --cwd $TEST_HOME/files\"}"
TILDE_TWO_WANT="{\"dir_typed\":\"~/a\",\"error\":\"usage: two directories: ~/a, ~/b\"}"
TILDE_ALONE='~'
TILDE_MISSING="~/no-such-run-agent-dir-$$"
# for run-agent-dirs.bats
TILDE_DIR_MISSING="~/no-such-run-agent-dir-$$"
