#!/bin/bash

scp -P 2222 ~/바탕화면/인턴/fyp/tb.sv sglee@SNU:~/test_code/
scp -P 2222 ~/바탕화면/인턴/fyp/decoder.v sglee@SNU:~/test_code/
scp -P 2222 ~/바탕화면/인턴/fyp/test.sh	  sglee@SNU:~/test_code/runsim
ssh -p 2222 sglee@SNU "cd test_code; bash -ic  runsim"
#ssh -p 2222 sglee@SNU "cd test_code; rm tb.sv"
#ssh -p 2222 sglee@SNU "cd test_code; rm decoder.v"
