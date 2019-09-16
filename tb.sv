/* Created By Sang Gu Lee... Jul 22th */
`timescale 1ns/10ps
//`define GEN_FILE		"gen.sg"	/* Generate bytecode file */


`define	SIM_LENGTH	1000
`define MODULE_TEST_LENGTH	50
`define CONTEXTID_LEN		4
`define SIMUL_MOD		1		/* Mode 1 = Complete Sim, Mode 0 = Function Test */
`define TEST_FUNCTION		WAYPOINT

/* Available Choices
	A_SYNC		= 0 
	I_SYNC		= 1
	TIME_STAMP	= 2
	ATOM  		= 3
	BRANCH		= 4 
	WAYPOINT	= 5
	TRIGGER		= 6
	CONTEXT_ID	= 7
	VMID		= 8
	EXCEPTION_RT	= 9
	IGNORE		= 10

 */

module test;

/* Testbench Control Parameters */
localparam 	CLK_HALF_CYCLE 		= 10; 		//clock half cycle 
localparam	MAX_PACKET_DATA_LEN	= 100;
localparam	TIMESTAMP_INTERVAL	= 1000;
localparam	SYNC_PACKET_PERIOD	= 40;
localparam	ASYNC_MAXLEN		= 50;
localparam	ASYNC_MINLEN		= 6;
localparam	CYCLE_ACCURATE		= 0;
localparam	USE_OF_RETURN_STACK	= 0;
//Initial Value
localparam	INIT_CONTEXTID		= 32'h00_00_00_ff;
localparam	INIT_ADDR		= 32'h80_00_00_00;
localparam	INIT_TIME		= 64'h100;
//Settings
localparam	DONOTGENERATE_EXCEPTION	= 0;
localparam	DETAIL_PRINT		= 1;
	
/* Input & Output */
bit 		iClk; 
bit 		iRsn;
bit 		idataEn;
bit  		[7:0] idata;
wire 		[31:0] oAddress;
wire 		oEn;

/* Packet Type */
typedef enum int { 

	A_SYNC		= 0, 
	I_SYNC		= 1,
	TIME_STAMP	= 2,
	ATOM  		= 3,
	BRANCH		= 4, 
	WAYPOINT	= 5,
	TRIGGER		= 6,
	CONTEXT_ID	= 7,
	VMID		= 8,
	EXCEPTION_RT	= 9,
	IGNORE		= 10	

} pkttype_t;


/* Packet */
typedef struct {

	pkttype_t 	packet_type;
	int 		packet_len;
	bit [7:0] 	packet_data[MAX_PACKET_DATA_LEN];

} packet_t;

/* Simulation Data */
typedef struct {

	//Shared Variable
	pkttype_t 	packet_type;
	int	 	packet_len;

	//Shared status info
	struct {
			bit		arm_thumb;
			bit		altis;
			bit		ns;
			bit		hyp;
			bit [31:0]	context_id;
			int		context_id_len;
			bit [31:0]	addr;
			bit [63:0]	timestamp;
	}stat;

	//Packet specific info
	union {

		struct {
			bit [1:0]	reason;
		} I_SYNC;
	
		struct {
			int		atom_cnt;
			bit [4:0]	atom_seq;	//The LSB is the recent waypoint
		} ATOM;

		struct {
			bit [8:0]	exception;
			int		addr_len;
			int		exception_len;
		} BRANCH;

		struct {
			int		addr_len;
			bit		info_len;
		} WAYPOINT;

		struct {
			bit[7:0]	vmid;		
		} VMID;
	
	}spec;
	

} feed_t;

/* Variables */
packet_t	packet[`SIM_LENGTH];
feed_t		info[`SIM_LENGTH];
bit [31:0]	result[`SIM_LENGTH];
bit [31:0]	answer_addr[`SIM_LENGTH];
int tp = 0;	//Current Test Point

/* Export File Descriptor */
int 	fd;


//int	ram_cnt;
int file_test,r;
int rdcnt,suc;
reg [7:0] test_vector[5000];
reg [31:0] answer_vector[5000];


/* Module Instance */
ptmdecoder #(`CONTEXTID_LEN) D1(.*);	//< Parameter # Contextid_len > 

/* Simulation Logic */
pkttype_t tv;

initial begin
	//fd= $fopen (`GEN_FILE, "wb");
	reset();


#10;

if( `SIMUL_MOD == 0 ) begin
/*Function only Test*/
		$display("\n\nFunction Checker\n");
		tv = `TEST_FUNCTION;
		mk_iden_seq(info,tv);
		mk_packet(packet,info);
		print_packet(info,packet,`MODULE_TEST_LENGTH);
		drive(`MODULE_TEST_LENGTH);
		check(info,result,`MODULE_TEST_LENGTH);
		
end else if( `SIMUL_MOD == 1 ) begin
/*Random Sequence*/
		$display("\n\nComplete Simulation\n");
		mk_rand_seq(info);
		mk_packet(packet,info);
		print_packet(info,packet,`SIM_LENGTH);
		drive(`SIM_LENGTH);
		check(info,result,`SIM_LENGTH);

end else if (`SIMUL_MOD ==  2) begin
/* Test Vector from File */
		
		//Read Test Vector
		file_test = $fopen("test_vect.txt", "r");
		if( file_test ) begin
			rdcnt = 0;
			while (1) begin
 				r = $fscanf(file_test, "%h\n", test_vector[rdcnt]);
				if( r != 1 )	 
					break;
				rdcnt++;
			end
			$fclose(file_test);
		end	

		//Drive 
		drive_testvect(rdcnt);

		//Read Answer
		file_test = $fopen("answer.txt", "r");	
		if( file_test ) begin
			rdcnt = 0;
			while (1) begin
 				r = $fscanf(file_test, "%h\n", answer_vector[rdcnt]);
				if( r != 1 )	 
					break;
				rdcnt++;
			end
			$fclose(file_test);
		end	


		$display("\n\n==============Result==================\n\n");
		suc = 0;
		//Compare with Answer
		for (int i =0; rdcnt > i ; i++) begin

			if(answer_vector[i] == result[i]) begin
				$display("[Correct: %x]", result[i]);
				suc++;
			end
			else
				$display("[Wrong: Test %x, Answer %x]", result[i], answer_vector[i]);

		end
		
		$display("\n[Result %4d/%4d Correct!]\n\n", suc, rdcnt);

end

	$finish();

end

/* Clock Generator */
always #CLK_HALF_CYCLE iClk = ~iClk;



/* Checker */
always @(posedge iClk ) begin

	if(oEn) begin
		$display("▶ OUTPUT (%5dns) Branch Data Out %x",$time,oAddress);
		result[tp] <=oAddress;
		tp++;
	end

end


/* Reset Task */
task reset();
	tp = 0;
	iRsn = 0;
	#60;
	iRsn = 1;

endtask


task automatic drive(int packet_len);

int i,j;

	for( i =0; packet_len > i; i++) begin
		j = 0;
		while(packet[i].packet_len > j) begin
			
			@(posedge iClk);

			/* Random data Enable */
			if( ranbit() & ranbit() )
				idataEn <= 1'b0;
			else begin
				idataEn <= 1'b1;
				$display("(%5dns) Data %x ",$time,packet[i].packet_data[j]);
				idata <= packet[i].packet_data[j];
				j++;
			end
		end
	end

	
	@(posedge iClk);
	@(posedge iClk);
	@(posedge iClk);

endtask


task automatic drive_testvect(int len);
int j =0;
		while(len > j) begin
			
			@(posedge iClk);

			/* Random data Enable */
			if( ranbit() & ranbit() )
				idataEn <= 1'b0;
			else begin
				$display("(%5dns) Data %x ",$time,test_vector[j]);
				idataEn <= 1'b1;
				idata <= test_vector[j];
				j++;
			end
		end
	
	@(posedge iClk);
	@(posedge iClk);
	@(posedge iClk);

endtask

function automatic void mk_iden_seq(ref feed_t info[`SIM_LENGTH], pkttype_t typ );

	//Initial Random Processor Status
	bit 		__arm_thumb 		= ranbit();
	bit 		__alits 		= __arm_thumb & ranbit();
	bit 		__ns  			= 0 ;
	bit 		__hyp  			= 0 ;
	const int 	__context_id_len	= `CONTEXTID_LEN	;
	bit [31:0] 	__context_id		= INIT_CONTEXTID;
	bit [31:0] 	__addr			= INIT_ADDR;
	bit [63:0] 	__timestamp		= INIT_TIME;	
	//pkttype_t	next_packet;

	int new_idx;
	bit [31:0] new_addr_mask, new_addr;



//Mandatory

	/* A_SYNC GENERATION*/
	info[0].packet_type = A_SYNC;
	info[0].packet_len  = $urandom_range(ASYNC_MINLEN,ASYNC_MAXLEN);

	/* I_SYNC GENERATION */
	info[1].stat.addr			= __addr;
	info[1].stat.timestamp			= __timestamp;
	info[1].stat.altis			= __alits;
	info[1].stat.ns				= __ns;
	info[1].stat.hyp			= __hyp;
	info[1].stat.context_id_len		= __context_id_len; 
	info[1].stat.context_id			= __context_id;
	info[1].stat.arm_thumb 			= __arm_thumb;

	info[1].packet_type = I_SYNC  ;
	info[1].packet_len = 6 + info[1].stat.context_id_len;
	info[1].spec.I_SYNC.reason = 2'b01;	//Trace On


//Selective Test
case (typ)

	TIME_STAMP	: begin

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
			info[i].packet_type = TIME_STAMP;
			info[i].stat.timestamp = info[i-1].stat.timestamp + $urandom_range(1,TIMESTAMP_INTERVAL);;
			info[i].packet_len = 1 + timestamp_len(info[i].stat.timestamp);
		end
	end


	EXCEPTION_RT	: begin	

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
				info[i].packet_type = EXCEPTION_RT; 
				info[i].packet_len  = 1;
		end

	end
	
	A_SYNC:	begin

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
				 info[i].packet_type = A_SYNC; 
				 info[i].packet_len  = $urandom_range(ASYNC_MINLEN,ASYNC_MAXLEN);
		end
	end
	
	I_SYNC : begin

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin

				info[i].packet_type 		= I_SYNC;
				info[i].stat.context_id_len	= __context_id_len;
				info[i].stat.arm_thumb 		= ranbit();
				info[i].stat.altis		= info[i].stat.arm_thumb  & ranbit();
				info[i].stat.ns			= ranbit();
				info[i].stat.hyp		= ranbit();
				info[i].stat.addr		= $random() & ( info[i].stat.arm_thumb ? {{31{1'b1}},1'b0} : {{30{1'b1}},2'b00});
				info[i].spec.I_SYNC.reason 	= $urandom_range(0,3);	//Trace On
				info[i].packet_len 		=  6 + info[i].stat.context_id_len;

				case(info[i].stat.context_id_len)

					0: info[i].stat.context_id	= 0;
					1: info[i].stat.context_id	= $urandom_range(0,255); //2^8 -1
					2: info[i].stat.context_id	= $urandom_range(0,65535);//2^16 -1
					4: info[i].stat.context_id	= $random();
				endcase		
	
		end

	end
	
	CONTEXT_ID: begin

			for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin

		  		 info[i].stat.context_id_len	= __context_id_len;
				 info[i].packet_len 	=  1	 + info[i].stat.context_id_len;
				 info[i].packet_type = CONTEXT_ID;
				 
				case(info[i].stat.context_id_len)
					0: info[i].stat.context_id	= 0;
					1: info[i].stat.context_id	= $urandom_range(0,255); //2^8 -1
					2: info[i].stat.context_id	= $urandom_range(256,65535);//2^16 -1
					4: info[i].stat.context_id	= $random();
				endcase		
			end
	
	end
	
	
	WAYPOINT: begin

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin

				info[i].packet_type 		= WAYPOINT;
				info[i].stat.arm_thumb 		= ranbit();
				info[i].stat.altis		= info[i].stat.arm_thumb  & ranbit();


				//Update only lower bits
				new_idx = $urandom_range(1,31);
				new_addr_mask = ({32{1'b1}} << new_idx);
				new_addr	 = $random();

				info[i].stat.addr		= (info[i-1].stat.addr & new_addr_mask) | ( new_addr & ~new_addr_mask);
				info[i].stat.addr		&= ( info[i].stat.arm_thumb ? {{31{1'b1}},1'b0} : {{30{1'b1}},2'b00});


				//Generate Full packet when mode changes
				if(info[i].stat.arm_thumb == info[i-1].stat.arm_thumb) 
					info[i].spec.WAYPOINT.addr_len 	= waypoint_len(info[i-1].stat.addr,info[i].stat.addr,info[i].stat.arm_thumb); 
				else
					info[i].spec.WAYPOINT.addr_len = 5;


				if( info[i].spec.WAYPOINT.addr_len >= 2 )
					info[i].spec.WAYPOINT.info_len	= ranbit();
				else
					info[i].spec.WAYPOINT.info_len	= 0;

				//Generate Full packet when Alit is Changes
				if(info[i].stat.altis != info[i-1].stat.altis) begin			
					info[i].spec.WAYPOINT.info_len 	= 1;
					info[i].spec.WAYPOINT.addr_len 	= 5;
				end

				info[i].packet_len = 1 + info[i].spec.WAYPOINT.addr_len +  info[i].spec.WAYPOINT.info_len;				

		end
	end
	
	VMID: begin

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
				 info[i].packet_type = VMID; 
				 info[i].packet_len  = 2;
				 info[i].spec.VMID.vmid = $urandom_range(0,255);
		end
	
	end
	
	BRANCH: begin
			
		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin

			info[i].packet_type 		= BRANCH;
			info[i].stat.arm_thumb 		= ranbit();
			info[i].stat.altis		= info[i].stat.arm_thumb  & ranbit();
			info[i].stat.ns			= ranbit();
			info[i].stat.hyp		= ranbit();



			new_idx 		= $urandom_range(1,31);
			new_addr_mask 		= ({32{1'b1}} << new_idx);
			new_addr		= $random();

			//Update only lower bits
			info[i].stat.addr		= (info[i-1].stat.addr & new_addr_mask) | ( new_addr & ~new_addr_mask);
			info[i].stat.addr		&= ( info[i].stat.arm_thumb ? {{31{1'b1}},1'b0} : {{30{1'b1}},2'b00});


			//mode change -> Full Address Packet Gen
			if( info[i].stat.arm_thumb ==  info[i-1].stat.arm_thumb)
				info[i].spec.BRANCH.addr_len 	= waypoint_len(info[i-1].stat.addr,info[i].stat.addr,info[i].stat.arm_thumb); 
			else
				info[i].spec.BRANCH.addr_len  = 5;


			//Do not generate Exception when addr_len is 1
			if(info[i].spec.BRANCH.addr_len != 1) begin
				if(DONOTGENERATE_EXCEPTION)
					info[i].spec.BRANCH.exception_len  = $urandom_range(0,0);
				else
					info[i].spec.BRANCH.exception_len  = $urandom_range(0,2);
			end
			else
				info[i].spec.BRANCH.exception_len  = 0;

			
			info[i].spec.BRANCH.exception = $urandom_range(0,255);
			info[i].packet_len = info[i].spec.BRANCH.addr_len + info[i].spec.BRANCH.exception_len ;
		end

	end
	
	IGNORE: begin
		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
				info[i].packet_type = IGNORE;
		 		info[i].packet_len  = 1;
		end
	end
	
	ATOM	: begin

		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
				info[i].packet_type = ATOM;	
				info[i].packet_len  = 1;
				info[i].spec.ATOM.atom_cnt = $urandom_range(1,5);
		
			if(USE_OF_RETURN_STACK) begin				
				info[i].spec.ATOM.atom_seq = $urandom_range(0,15);
			end else begin
			
				for(int j=0; info[i].spec.ATOM.atom_cnt > j ; j++) begin
					info[i].spec.ATOM.atom_seq[j] = 1'b1;	//N Atom Generate
				end
			end
	
		end	
	end
	
	TRIGGER : begin
		for(int i =2; `MODULE_TEST_LENGTH > i ;i++) begin
				 info[i].packet_type = TRIGGER; 
				 info[i].packet_len  = 1;
		end
	end
	
	
	
endcase
endfunction
	

/* Generate Random Seqence */
function automatic void mk_rand_seq(ref feed_t info[`SIM_LENGTH]);// feed_t info,int len);

	int idx = 0;

	//Initial Random Processor Status
	bit 		__arm_thumb 		= ranbit();
	bit 		__alits 		= __arm_thumb & ranbit();
	bit 		__ns  			= 0 ;
	bit 		__hyp  			= 0 ;
	const int 	__context_id_len	= `CONTEXTID_LEN	;	//This value is Fixed 
	bit [31:0] 	__context_id		= INIT_CONTEXTID;
	bit [31:0] 	__addr			= INIT_ADDR;
	bit [63:0] 	__timestamp		= INIT_TIME;	
	pkttype_t	next_packet;

	int new_idx;
	bit [31:0] new_addr_mask, new_addr;


	info[0].stat.arm_thumb 			= __arm_thumb;
	info[0].stat.altis			= __alits;
	info[0].stat.ns				= __ns;
	info[0].stat.hyp			= __hyp;
	info[0].stat.context_id_len		= __context_id_len; 
	info[0].stat.context_id			= __context_id;
	info[0].stat.addr			= __addr;
	info[0].stat.timestamp			= __timestamp;


	/* A_SYNC GENERATION*/
	info[0].packet_type = A_SYNC;
	info[0].packet_len  = $urandom_range(ASYNC_MINLEN,ASYNC_MAXLEN);

	/* I_SYNC GENERATION */
	info[1] = info[0];
	info[1].packet_type = I_SYNC  ;
	info[1].packet_len = 6 + info[1].stat.context_id_len;
	info[1].spec.I_SYNC.reason = 2'b01;
	/* Time Stamp GENERATION */
	info[2] = info[1];
	info[2].packet_type = TIME_STAMP;
	info[2].packet_len = 1 + timestamp_len(info[2].stat.timestamp);

	for(int i =3; `SIM_LENGTH > i ;i++) begin
		
		info[i] = info[i-1];

		__timestamp += $urandom_range(1,TIMESTAMP_INTERVAL);


		/*Assumptions
			ISync 		= Periodic Generation
			ASync 		= Periodic Generation
			Timestamp	= Periodic Generation
			ATOM  = Gen N Atom when condition False, Gen E Atom When condition True( only when return stack is enabled) 

		*/

		//Sync Packet	
		if( i % SYNC_PACKET_PERIOD == 0 ) begin
			next_packet = A_SYNC;
		end else if( i % SYNC_PACKET_PERIOD == 1) begin
			next_packet = I_SYNC;
		end else if ( i % SYNC_PACKET_PERIOD == 2 ) begin
			next_packet = TIME_STAMP;
		end else  begin
			// Pick One Random Action
			next_packet = $urandom_range(3,10);
		end


		case (next_packet)

			/* Periodic */
			A_SYNC		:	begin
				 info[i].packet_type = A_SYNC; 
				 info[i].packet_len  = $urandom_range(ASYNC_MINLEN,ASYNC_MAXLEN);
			end
	 		/* Periodic */
			I_SYNC		:	begin

				info[i].packet_type 		= I_SYNC;
				info[i].stat.context_id_len	= __context_id_len;
				info[i].stat.arm_thumb 		= ranbit();
				info[i].stat.altis		= info[i].stat.arm_thumb  & ranbit();
				info[i].stat.ns			= ranbit();
				info[i].stat.hyp		= ranbit();
				info[i].stat.addr		= $random() & ( info[i].stat.arm_thumb ? {{31{1'b1}},1'b0} : {{30{1'b1}},2'b00});
				info[i].spec.I_SYNC.reason 	= $urandom_range(0,3);
				info[i].packet_len 		=  6 + info[i].stat.context_id_len;

				case(info[i].stat.context_id_len)

					0: info[i].stat.context_id	= 0;
					1: info[i].stat.context_id	= $urandom_range(0,255); //2^8 -1
					2: info[i].stat.context_id	= $urandom_range(0,65535);//2^16 -1
					4: info[i].stat.context_id	= $random();
				endcase		

			end

			/* Periodic */
			TIME_STAMP 	:	 begin
				info[i].packet_type = TIME_STAMP;
				info[i].stat.timestamp = __timestamp;
				info[i].packet_len = 1 + timestamp_len(info[i].stat.timestamp);
			end
	
			ATOM  		:	begin

				info[i].packet_type = ATOM;	
				info[i].packet_len  = 1;
				info[i].spec.ATOM.atom_cnt = $urandom_range(1,5);
			
				if(USE_OF_RETURN_STACK) begin				
					info[i].spec.ATOM.atom_seq = $urandom_range(0,15);
				end else begin
				
					for(int j=0; info[i].spec.ATOM.atom_cnt > j ; j++) begin
						info[i].spec.ATOM.atom_seq[j] = 1'b1;	//N Atom Generate
					end
				end

			end

			BRANCH		:	begin

				info[i].packet_type 		= BRANCH;
				info[i].stat.arm_thumb 		= ranbit();
				info[i].stat.altis		= info[i].stat.arm_thumb  & ranbit();
				info[i].stat.ns			= ranbit();
				info[i].stat.hyp		= ranbit();
				

				new_idx 		= $urandom_range(1,31);
				new_addr_mask 		= ({32{1'b1}} << new_idx);
				new_addr		= $random();
	
				//Update only lower bits
				info[i].stat.addr		= (info[i-1].stat.addr & new_addr_mask) | ( new_addr & ~new_addr_mask);
				info[i].stat.addr		&= ( info[i].stat.arm_thumb ? {{31{1'b1}},1'b0} : {{30{1'b1}},2'b00});
	
	
				//mode change -> Full Address Packet Gen
				if( info[i].stat.arm_thumb ==  info[i-1].stat.arm_thumb)
					info[i].spec.BRANCH.addr_len 	= waypoint_len(info[i-1].stat.addr,info[i].stat.addr,info[i].stat.arm_thumb); 
				else
					info[i].spec.BRANCH.addr_len  = 5;
	
	
				//Do not generate Exception when addr_len is 1
				if(info[i].spec.BRANCH.addr_len != 1) begin
					if(DONOTGENERATE_EXCEPTION)
						info[i].spec.BRANCH.exception_len  = $urandom_range(0,0);
					else
						info[i].spec.BRANCH.exception_len  = $urandom_range(0,2);
				end else
					info[i].spec.BRANCH.exception_len  = 0;
	
				
				info[i].spec.BRANCH.exception = $urandom_range(0,255);
				info[i].packet_len = info[i].spec.BRANCH.addr_len + info[i].spec.BRANCH.exception_len ;
	
			end

			WAYPOINT	:	begin

				info[i].packet_type 		= WAYPOINT;
				info[i].stat.arm_thumb 		= ranbit();
				info[i].stat.altis		= info[i].stat.arm_thumb  & ranbit();
				

				//Update only lower bits
				new_idx = $urandom_range(1,31);
				new_addr_mask = ({32{1'b1}} << new_idx);
				new_addr	 = $random();

				info[i].stat.addr		= (info[i-1].stat.addr & new_addr_mask) | ( new_addr & ~new_addr_mask);
				info[i].stat.addr		&= ( info[i].stat.arm_thumb ? {{31{1'b1}},1'b0} : {{30{1'b1}},2'b00});


				//Generate Full packet when mode changes
				if(info[i].stat.arm_thumb == info[i-1].stat.arm_thumb) 
					info[i].spec.WAYPOINT.addr_len 	= waypoint_len(info[i-1].stat.addr,info[i].stat.addr,info[i].stat.arm_thumb); 
				else
					info[i].spec.WAYPOINT.addr_len = 5;

				if( info[i].spec.WAYPOINT.addr_len >= 2 )
					info[i].spec.WAYPOINT.info_len	= ranbit();
				else
					info[i].spec.WAYPOINT.info_len	= 0;

				//Generate Full packet when Alit is Changes
				if(info[i].stat.altis != info[i-1].stat.altis) begin			
					info[i].spec.WAYPOINT.info_len 	= 1;
					info[i].spec.WAYPOINT.addr_len 	= 5;
				end

				info[i].packet_len = 1 + info[i].spec.WAYPOINT.addr_len +  info[i].spec.WAYPOINT.info_len;	
		
			end

			TRIGGER		:	begin
				 info[i].packet_type = TRIGGER; 
				 info[i].packet_len  = 1;
			end

			CONTEXT_ID 	:	begin

				if( __context_id_len > 0 ) begin
					info[i].stat.context_id_len	= __context_id_len;
				 	info[i].packet_len 	=  1	 + info[i].stat.context_id_len;
				 	info[i].packet_type = CONTEXT_ID;
				 
					case(info[i].stat.context_id_len)
						0: info[i].stat.context_id	= 0;
						1: info[i].stat.context_id	= $urandom_range(0,255); //2^8 -1
						2: info[i].stat.context_id	= $urandom_range(256,65535);//2^16 -1
						4: info[i].stat.context_id	= $random();
					endcase
				end
				
			end
			VMID		:	begin
				 info[i].packet_type = VMID; 
				 info[i].packet_len  = 2;
				 info[i].spec.VMID.vmid = $urandom_range(0,255);
			end
	
			EXCEPTION_RT 	:	begin
				info[i].packet_type = EXCEPTION_RT; 
				info[i].packet_len  = 1;
			end
			IGNORE	     	: 	 begin
				info[i].packet_type = IGNORE;
		 		info[i].packet_len  = 1;
			end

		endcase
	end



endfunction


/* Packet Generator */
function automatic void mk_packet(ref packet_t packet[`SIM_LENGTH], feed_t info[`SIM_LENGTH]);

	//Temp Storage
	int	i;
	bit [7:0] pkheader;
	bit [7:0] byte_packet[MAX_PACKET_DATA_LEN];

for(int k =0; `SIM_LENGTH > k ; k++) begin

	packet[k].packet_type 	= info[k].packet_type;
	packet[k].packet_len 	= info[k].packet_len;

	case (packet[k].packet_type)

		A_SYNC	:begin

		 	pkheader =  8'b0000_0000;

			for(int i =0; packet[k].packet_len -1 > i; i++) begin
				byte_packet[i] = 0;
			end

			byte_packet[packet[k].packet_len-2] = 8'b1000_0000;
		end

		I_SYNC	:begin

			pkheader =  8'b0000_1000;

			byte_packet[0][0]	= info[k].stat.arm_thumb;
			byte_packet[0][7:1] 	= info[k].stat.addr[7:1];
			byte_packet[1]	 	= info[k].stat.addr[15:8];
			byte_packet[2]	 	= info[k].stat.addr[23:16];
			byte_packet[3]	 	= info[k].stat.addr[31:24];
			byte_packet[4][6:5]	= info[k].spec.I_SYNC.reason;
			byte_packet[4][3]	= info[k].stat.ns;
			byte_packet[4][2]	= info[k].stat.altis;
			byte_packet[4][1]	= info[k].stat.hyp;
			byte_packet[4][0]	= 1'b1;


			case(info[k].stat.context_id_len)
		
				1: byte_packet[5] = info[k].stat.context_id[7:0];

				2: begin
					byte_packet[5] = info[k].stat.context_id[7:0];
					byte_packet[6] = info[k].stat.context_id[15:8];
				end

				4: begin
					byte_packet[5] = info[k].stat.context_id[7:0];
					byte_packet[6] = info[k].stat.context_id[15:8];
					byte_packet[7] = info[k].stat.context_id[23:16];
					byte_packet[8] = info[k].stat.context_id[31:24];
				end


			endcase

		end

		ATOM	:begin

			case (info[k].spec.ATOM.atom_cnt)

				1: pkheader =  8'b1000_0100 | {2'b00,info[k].spec.ATOM.atom_seq,1'b0};
				2: pkheader =  8'b1000_1000 | {2'b00,info[k].spec.ATOM.atom_seq,1'b0}; 
				3: pkheader =  8'b1001_0000 | {2'b00,info[k].spec.ATOM.atom_seq,1'b0}; 
				4: pkheader =  8'b1010_0000 | {2'b00,info[k].spec.ATOM.atom_seq,1'b0};
				5: pkheader =  8'b1100_0000 | {2'b00,info[k].spec.ATOM.atom_seq,1'b0};  

			endcase

		end					  

		BRANCH	:begin

			if (!info[k].stat.arm_thumb) begin	//ARM Mode

				case(info[k].spec.BRANCH.addr_len)
					1: begin 
						pkheader = {1'b0,info[k].stat.addr[7:2],1'b1};
						end
					2: begin
						pkheader = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[0] = {info[k].spec.BRANCH.exception_len ==0 ? 2'b00: 2'b01,info[k].stat.addr[13:8]};
						end
					3: begin
						pkheader = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[0] = {1'b1,info[k].stat.addr[14:8]};
						byte_packet[1] = {info[k].spec.BRANCH.exception_len ==0 ? 2'b00: 2'b01, info[k].stat.addr[20:15]};
						end
					4: begin
						pkheader = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[0] = {1'b1,info[k].stat.addr[14:8]};
						byte_packet[1] = {1'b1,info[k].stat.addr[21:15]};
						byte_packet[2] = {info[k].spec.BRANCH.exception_len ==0 ? 2'b00: 2'b01, info[k].stat.addr[27:22]};
						end
					5: begin
						pkheader = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[0] = {1'b1,info[k].stat.addr[14:8]};
						byte_packet[1] = {1'b1,info[k].stat.addr[21:15]};
						byte_packet[2] = {1'b1,info[k].stat.addr[28:22]};
						byte_packet[3] = {info[k].spec.BRANCH.exception_len ==0 ? 5'b00001: 5'b01001,info[k].stat.addr[31:29]};
						end
				endcase

			end else begin		//Thumb Mode

				case(info[k].spec.BRANCH.addr_len)
					1: begin 
						pkheader = {1'b0,info[k].stat.addr[6:1],1'b1};
						end
					2: begin
						pkheader = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[0] = {info[k].spec.BRANCH.exception_len ==0 ? 2'b00: 2'b01,info[k].stat.addr[12:7]};
						end
					3: begin
						pkheader = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[0] = {1'b1,info[k].stat.addr[13:7]};
						byte_packet[1] = {info[k].spec.BRANCH.exception_len ==0 ? 2'b00: 2'b01, info[k].stat.addr[19:14]};
						end
					4: begin
						pkheader = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[0] = {1'b1,info[k].stat.addr[13:7]};
						byte_packet[1] = {1'b1,info[k].stat.addr[20:14]};
						byte_packet[2] = {info[k].spec.BRANCH.exception_len ==0 ? 2'b00: 2'b01, info[k].stat.addr[26:21]};
						end
					5: begin
						pkheader = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[0] = {1'b1,info[k].stat.addr[13:7]};
						byte_packet[1] = {1'b1,info[k].stat.addr[20:14]};
						byte_packet[2] = {1'b1,info[k].stat.addr[27:21]};
						byte_packet[3] = {info[k].spec.BRANCH.exception_len ==0 ? 4'b0001: 4'b0101,info[k].stat.addr[31:28]};
						end
				endcase


			end

		
			case(info[k].spec.BRANCH.exception_len)
				1: byte_packet[info[k].spec.BRANCH.addr_len-1] = {1'b0, info[k].stat.altis,1'b0,info[k].spec.BRANCH.exception_len[3:0],info[k].stat.ns};
				2: begin
					byte_packet[info[k].spec.BRANCH.addr_len-1] = {1'b1, info[k].stat.altis,1'b0,info[k].spec.BRANCH.exception[3:0],info[k].stat.ns};
					byte_packet[info[k].spec.BRANCH.addr_len ] = {2'b00, info[k].stat.hyp,info[k].spec.BRANCH.exception[8:4]}; 
				end
			endcase

	


		end						  


		WAYPOINT:begin

			pkheader =  8'b0111_0010; 

			if( !info[k].stat.arm_thumb ) begin	//arm mode

				case(info[k].spec.WAYPOINT.addr_len)
				
					1: byte_packet[0] = {1'b0,info[k].stat.addr[7:2],1'b1};
				
					2: begin
						byte_packet[0] = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[1] = {info[k].spec.WAYPOINT.info_len? 2'b01:2'b00,info[k].stat.addr[13:8]};
					end
					3: begin
						byte_packet[0] = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[1] = {1'b1,info[k].stat.addr[14:8]};
						byte_packet[2] = {info[k].spec.WAYPOINT.info_len? 2'b01:2'b00,info[k].stat.addr[20:15]};
					end
					4: begin
						byte_packet[0] = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[1] = {1'b1,info[k].stat.addr[14:8]};
						byte_packet[2] = {1'b1,info[k].stat.addr[21:15]};
						byte_packet[3] = {info[k].spec.WAYPOINT.info_len? 2'b01:2'b00,info[k].stat.addr[27:22]};
					end
					5: begin

						byte_packet[0] = {1'b1,info[k].stat.addr[7:2],1'b1};
						byte_packet[1] = {1'b1,info[k].stat.addr[14:8]};
						byte_packet[2] = {1'b1,info[k].stat.addr[21:15]};
						byte_packet[3] = {1'b1,info[k].stat.addr[28:22]};
						byte_packet[4] = {info[k].spec.WAYPOINT.info_len? 5'b01001:5'b00001,info[k].stat.addr[31:29]};
					end

				endcase
		
						if(info[k].spec.WAYPOINT.info_len)
							byte_packet[info[k].spec.WAYPOINT.addr_len] = 8'b0000_0000;


			end else begin			//Thumb mode

				case(info[k].spec.WAYPOINT.addr_len)
				
					1: byte_packet[0] = {1'b0,info[k].stat.addr[6:1],1'b1};
				
					2: begin
						byte_packet[0] = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[1] = {info[k].spec.WAYPOINT.info_len? 2'b01:2'b00,info[k].stat.addr[12:7]};
					end
					3: begin
						byte_packet[0] = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[1] = {1'b1,info[k].stat.addr[13:7]};
						byte_packet[2] = {info[k].spec.WAYPOINT.info_len? 2'b01:2'b00,info[k].stat.addr[19:14]};
					end
					4: begin
						byte_packet[0] = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[1] = {1'b1,info[k].stat.addr[13:7]};
						byte_packet[2] = {1'b1,info[k].stat.addr[20:14]};
						byte_packet[3] = {info[k].spec.WAYPOINT.info_len? 2'b01:2'b00,info[k].stat.addr[26:21]};
					end
					5: begin

						byte_packet[0] = {1'b1,info[k].stat.addr[6:1],1'b1};
						byte_packet[1] = {1'b1,info[k].stat.addr[13:7]};
						byte_packet[2] = {1'b1,info[k].stat.addr[20:14]};
						byte_packet[3] = {1'b1,info[k].stat.addr[27:21]};
						byte_packet[4] = {info[k].spec.WAYPOINT.info_len? 4'b0101:4'b0001,info[k].stat.addr[31:28]};
					end
				endcase


						if(info[k].spec.WAYPOINT.info_len)
							byte_packet[info[k].spec.WAYPOINT.addr_len] = info[k].stat.altis ? 8'b01_000000 : 8'b00_000000;

			end

		
		end
	
		TRIGGER	:begin
		 	pkheader =  8'b0000_1100; 
		

		end

		CONTEXT_ID:begin

			pkheader =  8'b0110_1110;

			case(info[k].stat.context_id_len)

				1: byte_packet[0] = info[k].stat.context_id[7:0];

				2: begin

				byte_packet[0] = info[k].stat.context_id[7:0];
				byte_packet[1] = info[k].stat.context_id[15:8];

				end

				4: begin

				byte_packet[0] = info[k].stat.context_id[7:0];
				byte_packet[1] = info[k].stat.context_id[15:8];
				byte_packet[2] = info[k].stat.context_id[23:16];
				byte_packet[3] = info[k].stat.context_id[31:24];
				end

			endcase


		end

		VMID	:begin

			pkheader =  8'b0011_1100;

			byte_packet[0] = info[k].spec.VMID.vmid;

		end
 
		TIME_STAMP:begin
			pkheader =  8'b0100_0010;

			for(i =0; info[k].packet_len - 2 > i; i++ ) begin
				byte_packet[i] = {1'b1,info[k].stat.timestamp[(7*i + 6) -:7]};
			end
				byte_packet[i] = {1'b0,info[k].stat.timestamp[(7*i + 6) -:7]};
		end
						  
		EXCEPTION_RT:begin
			pkheader =  8'b0111_0110; 

		end

		IGNORE	:begin

			pkheader =  8'b0110_0110; 

		end

	endcase

	//Write Header
		packet[k].packet_data[0]	= pkheader;

	//Write Data
	for (int i = 1 ; packet[k].packet_len > i; i++) begin
		packet[k].packet_data[i] 	= byte_packet[i-1];
	end
	//export_packet(packet[k]);


end


endfunction


/* Export To File */
function automatic void export_packet(packet_t packet);
	for(int i = 0; packet.packet_len > i; i++) begin
		$fwrite(fd,"%c",packet.packet_data[i]);
	end
endfunction


function automatic void check(feed_t info[`SIM_LENGTH],bit [31:0] result[`SIM_LENGTH], int length);

	int j =0;
	int suc =0;

	$display("\n\nAnswer The Output Value Should be .....\n");
	for(int i =0; length > i ; i++) begin
		if(  info[i].packet_type == BRANCH ) begin
			$display("[ BRANCH ] ## (Info) Mode %s, Addr: 0x%x, Altis %b, Hyp %b ",info[i].stat.arm_thumb?"THUMB":"ARM", info[i].stat.addr,info[i].stat.altis,info[i].stat.hyp);
			answer_addr[j++] = info[i].stat.addr;
		end
	end

	$display("\n[ Test Results ]\n");

	for(int i =0; j > i ; i++) begin
		if(result[i] == answer_addr[i] ) begin
			$display("[Correct: : Result %8x]",result[i]);
			suc++;
		end else
			$display("[Err	  : Result %8x , Answer %8x]",result[i], answer_addr[i]);
	end

	$display("\n\n[Sim Finished] %3d Branch Addr : Correct %3d, Err %3d \n\n",j, suc, j - suc);

endfunction


function automatic void print_packet(feed_t info[`SIM_LENGTH],packet_t packet[`SIM_LENGTH], int length);

for(int i =0; length > i ; i++) begin
	case( info[i].packet_type )
		A_SYNC 		: begin
			$write("[ A_SYNC      ]");
		end
		I_SYNC 		: begin
			$write("[ I_SYNC      ] ## (Info) Mode %s, Addr: 0x%x, Altis %b, Hyp %b, NS %b, CID 0x%x", info[i].stat.arm_thumb? "THUMB":"ARM", info[i].stat.addr,  info[i].stat.altis, info[i].stat.hyp, info[i].stat.ns, info[i].stat.context_id);
		end
		ATOM   		: begin
			$write("[ ATOM        ] ## (Info) %1d Atoms ",info[i].spec.ATOM.atom_cnt);

				for(int j =0; info[i].spec.ATOM.atom_cnt > j; j++) begin
					$write("[%1dth] %1s ",j,info[i].spec.ATOM.atom_seq[j] ? "N":"E" );
				end
			
			
		end
		BRANCH 		: begin
			if(info[i].spec.BRANCH.exception_len > 0)
			$write("[ BRANCH      ] ## (Info) Mode %s, Addr: 0x%x, Altis %b, Hyp %b ",info[i].stat.arm_thumb?"THUMB":"ARM", info[i].stat.addr,info[i].stat.altis,info[i].stat.hyp);
			else
			$write("[ BRANCH      ] ## (Info) Mode %s, Addr: 0x%x",info[i].stat.arm_thumb?"THUMB":"ARM", info[i].stat.addr);
		end
		WAYPOINT	: begin
			$write("[ WAYPOINT    ] ## (Info) Mode %s, Addr: 0x%x, Altis %b [addr %1d, info %1d]",info[i].stat.arm_thumb?"THUMB":"ARM",info[i].stat.addr,info[i].stat.altis,info[i].spec.WAYPOINT.addr_len,info[i].spec.WAYPOINT.info_len);
		end
		TRIGGER		: begin
			$write("[ TRIGGER     ]");
		end
		CONTEXT_ID	: begin
			$write("[ CONTEXT     ] ## (Info) Context id 0x%8x ", info[i].stat.context_id );
		end
		VMID		: begin
			$write("[ VMID        ] ## (Info) VMID 0x%4x ", info[i].spec.VMID.vmid);
		end
		TIME_STAMP	: begin
			$write("[ TIMESTAMP   ] ## (Info) TIME 0x%8x", info[i].stat.timestamp);
		end
		EXCEPTION_RT	: begin
			$write("[ EXCEPTIONRT ]");
		end
		IGNORE		: begin
			$write("[ IGNORE      ]");
		end	

	endcase


	if ( DETAIL_PRINT == 1 ) begin
			$write(" >>>> Sequence [");
		for (int j =0;  info[i].packet_len > j ; j++) begin
			$write("%x, ", packet[i].packet_data[j]);
		end
		$write(" ]\n");
	end

end

endfunction




function automatic int timestamp_len(bit [63:0]	timestamp);

int j = 0;
	for(int i =63; i > 0 ; i--) begin
		if(timestamp[i] == 1'b1) begin
			j = i;
			break;
		end
		
	end	
	

return j / 7 + 1;
endfunction


function automatic int waypoint_len(bit [31:0] pre_addr, bit [31:0] new_addr,int mode );


int j = 0;
	for(int i =31; i > 0 ; i--) begin
		if(pre_addr[i] != new_addr[i]) begin
			j = i;
			break;
		end
		
	end	


if(mode == 0 ) begin

	if(j <= 7 )
		return 1;
	else if( j <= 13)
		return 2;
	else if( j <= 20)
		return 3;
	else if( j <= 27)
		return 4;
	else
		return 5;

end else  begin

	if(j <= 6 )
		return 1;
	else if( j <= 12)
		return 2;
	else if( j <= 19)
		return 3;
	else if( j <= 26)
		return 4;
	else
		return 5;

end



endfunction



function automatic bit ranbit();
	return $urandom_range(0,1);
endfunction



endmodule

