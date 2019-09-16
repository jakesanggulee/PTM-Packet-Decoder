#!/bin/bash


args="-clean -access rwc -input run.tcl tb.sv decoder.v"
sim_len=1500


printf "\nPTM Decoder Tester\n\n"

while [ 1 ]
do


	printf "Test Mode:\n[1] Function Only Check \n[2] Artificial Test Vector \n[3] Test Vector from File\n[4] Exit\n\n"
	read -p "Test Mode Select:  "	_testmode

	if   [ $_testmode -eq 1 ] ; then
		printf "[Function List]\n\n"
		printf "A_SYNC  	= 0\n"
		printf	"I_SYNC		= 1\n"
		printf "TIME_STAMP	= 2\n"
		printf "ATOM  		= 3\n"
		printf "BRANCH		= 4\n"
		printf "WAYPOINT	= 5\n"
		printf "TRIGGER		= 6\n"
		printf "CONTEXT_ID	= 7\n"
		printf "VMID		= 8\n"
		printf "EXCEPTION_RT	= 9\n"
		printf "IGNORE		= 10\n\n"
		read -p "Select :  "	func

		irun "$args +define+TEST_FUNCTION=$func +define+SIMUL_MOD=0"

	elif [ $_testmode -eq 2 ] ; then
		
		printf "Simulation Length?"
		read sim_len
		
		if [ $sim_len -gt 10 ] ; then
			irun "$args +define+SIMUL_MOD=1 +define+SIM_LENGTH=$sim_len"
		else
			printf " Value should be greater than 10\n"
		fi

	elif [ $_testmode -eq 3 ] ; then


		awk -F"[][ ]" '{print $1}' a_out.txt | sed '/^$/d'	>  test_vect.txt
		awk -F"[][ ]" '{print $1}' b_out.txt | sed '/^$/d'	>> test_vect.txt
		awk -F"[][ ]" '{print $1}' c_out.txt | sed '/^$/d'	>> test_vect.txt

		grep "DUMP:" a_out.txt | awk '{print $3}'|sed 's/^..//' >  answer.txt
		grep "DUMP:" b_out.txt | awk '{print $3}'|sed 's/^..//' >> answer.txt
		grep "DUMP:" c_out.txt | awk '{print $3}'|sed 's/^..//' >> answer.txt


		printf "\n\nFile \"test_vect.txt\" Generated! \n"
	      	printf "File \"answer.txt\"    Generated! \n\n"

		 irun "$args +define+SIMUL_MOD=2"

	else
		exit 0;
	fi

done


