docker run -it --rm \
    -v "${PWD}/scripts/autobahn-config:/config" \
    -v "${PWD}/.build/reports:/reports" \
    -p 9001:9001 \
    --name fuzzingserver \
    crossbario/autobahn-testsuite
