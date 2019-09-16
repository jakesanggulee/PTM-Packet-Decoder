#!/bin/bash

awk -vORS="" -F"[][ ]" '{print $1}' a_out.txt >> testvector.txt
awk -vORS="" -F"[][ ]" '{print $1}' b_out.txt >> testvector.txt
awk -vORS="" -F"[][ ]" '{print $1}' c_out.txt >> testvector.txt


irun			\ 
	-clean		\
	-access rwc 	\
       	+define+TEST=20 \
	-input run.tcl	\
	tb.sv		\
	decoder.v

