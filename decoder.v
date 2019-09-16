/* Created By Sang Gu Lee... Jul 27th */

`define	VERBOSE

module ptmdecoder 	
		#(
			/* Parameters */
			parameter 	CONTEXTID_LEN			= 4
		)(
			/* In-Out */
			input iClk,
			input iRsn,
			input idataEn,
			input [7:0] idata,
			output reg [31:0] oAddress,
			output reg oEn
		);

/* Constants */
localparam	L				= 1'b0;
localparam	H				= 1'b1;
/* Packet Header */
localparam	ASYNC_HEADER			= 8'b0000_0000;
localparam	ASYNC_END			= 8'b1000_0000;
localparam	ISYNC_HEADER			= 8'b0000_1000;
localparam	ATOM_HEADER			= 8'b1xxx_xxx0;
localparam	BRANCH_HEADER			= 8'bxxxx_xxx1;
localparam	WAYPOINT_HEADER			= 8'b0111_0010;			
localparam	TRIGGER_HEADER			= 8'b0000_1100;
localparam	CONTEXTID_HEADER		= 8'b0110_1110;	
localparam	VMID_HEADER			= 8'b0011_1100;
localparam	TIMESTAMP_HEADER		= 8'b0100_0x10;
localparam	EXCEPTIONRT_HEADER		= 8'b0111_0110;
localparam	IGNORE_HEADER			= 8'b0110_0110;
/* Possible Stages To Perform */
localparam	DECODE_HEADER			= 3'b000;
localparam	DECODE_ASYNC_PAYLOAD		= 3'b001;
localparam	DECODE_ISYNC_PAYLOAD		= 3'b010;
localparam	DECODE_WAYPOINT_BRANCH_PAYLOAD	= 3'b011;
localparam	DECODE_TIMESTAMP_PAYLOAD	= 3'b100;
localparam	DECODE_BRANCH_EXCEPTION		= 3'b101;
localparam	DECODE_CONTEXTID		= 3'b110;
localparam	DROP_PAYLOAD			= 3'b111;
/* Constant Values */
localparam	ARMMODE				= 0;
localparam	THUMBMODE			= 1;
localparam	CONTINUE_BIT			= 7;
localparam	INFORMATION_BIT			= 6;
localparam	MODE_BIT			= 4;
localparam	MAX_TIMESTAMP_LEN		= 8;
localparam	ISYNC_PAYLOAD_LEN		= 4;

/* Declare Variables */
reg[31:0]		AddressTmp;
reg[2:0]		stage;
reg[4:0]		read_cnt;
reg			arm_thumb, isbranch;


/* Stage Update */
always @ ( posedge iClk or negedge iRsn ) begin

	/* Reset Logic */
	if(!iRsn)  begin
		stage	<= DECODE_HEADER;
	end
	/* Normal Operation Logic */
	else if (idataEn) begin
		case(stage)
			DECODE_HEADER: 
					casex(idata)
						ASYNC_HEADER	: 	stage <= DECODE_ASYNC_PAYLOAD;
						ISYNC_HEADER	: 	stage <= DECODE_ISYNC_PAYLOAD;
						WAYPOINT_HEADER	: 	stage <= DECODE_WAYPOINT_BRANCH_PAYLOAD;
						BRANCH_HEADER	:
									if(idata[CONTINUE_BIT] == H) //has next byte
										stage <= DECODE_WAYPOINT_BRANCH_PAYLOAD;	
									else
										stage <= DECODE_HEADER;
							
						TIMESTAMP_HEADER	: stage <= DECODE_TIMESTAMP_PAYLOAD;
						VMID_HEADER		: stage <= DROP_PAYLOAD;	
						CONTEXTID_HEADER	: stage <= DECODE_CONTEXTID;
						default			: stage <= DECODE_HEADER;
					endcase

			DECODE_ASYNC_PAYLOAD	:	
					if(idata == ASYNC_END)
						stage	<= DECODE_HEADER;		
					else				
						stage	<= DECODE_ASYNC_PAYLOAD;
			DECODE_ISYNC_PAYLOAD	:
					if( read_cnt == CONTEXTID_LEN + ISYNC_PAYLOAD_LEN )
						stage	<= DECODE_HEADER;
					else
						stage	<= DECODE_ISYNC_PAYLOAD;
			DECODE_WAYPOINT_BRANCH_PAYLOAD:
					if( idata[CONTINUE_BIT] == H) 
						stage	<= DECODE_WAYPOINT_BRANCH_PAYLOAD;	
					else if( idata[INFORMATION_BIT] == H && read_cnt != 0)
						stage	<= DECODE_BRANCH_EXCEPTION;	
					else
						stage	<= DECODE_HEADER;	
			DECODE_BRANCH_EXCEPTION	:
					if( idata[CONTINUE_BIT] == H)
						stage	<= DROP_PAYLOAD;
					else
						stage	<= DECODE_HEADER;
			DECODE_TIMESTAMP_PAYLOAD:
					if( idata[CONTINUE_BIT] == H && MAX_TIMESTAMP_LEN > read_cnt)
						stage	<= DECODE_TIMESTAMP_PAYLOAD;
					else			
						stage	<= DECODE_HEADER;	

			DECODE_CONTEXTID	:
					if( read_cnt >= CONTEXTID_LEN - 1)
						stage	<= DECODE_HEADER;
					else
						stage	<= DECODE_CONTEXTID;

			DROP_PAYLOAD:		stage	<= DECODE_HEADER;	//always drop next packet

			
		endcase


	end

end

/* Address & Mode Update */
always @ ( posedge iClk or negedge iRsn ) begin
	/* Reset Logic */
	if(!iRsn) begin 
		oAddress	<= {32{L}}; 
		AddressTmp	<= {32{L}};
		arm_thumb	<=	L;
	end
	/* Normal Operation Logic */
	else if ( idataEn ) begin

		case(stage)

			DECODE_HEADER		:	if( idata[0] == H) begin //if branch 
								if(idata[CONTINUE_BIT] == H)  begin	// has next byte
									AddressTmp[5:0] <= idata[6:1];
								end else begin
									if(arm_thumb)	oAddress[6:1] 	<= idata[6:1];
									else		oAddress[7:2] 	<= idata[6:1];
								end
							end

			DECODE_ISYNC_PAYLOAD	: 	case(read_cnt)
								0: begin	oAddress[0]	<= L;
										oAddress[7:1] 	<= idata[7:1];
										arm_thumb 	<= idata[0]; 
								end
								1: 		oAddress[15:8]	<= idata[7:0];
								2: 		oAddress[23:16] <= idata[7:0];
								3: 		oAddress[31:24] <= idata[7:0];
							endcase

			DECODE_WAYPOINT_BRANCH_PAYLOAD: 
				
							if(idata[CONTINUE_BIT] == H) begin // has next byte	

								case(read_cnt)
									0:	AddressTmp[5:0] 	<= idata[6:1];
									1:	AddressTmp[12:6] 	<= idata[6:0];
									2:	AddressTmp[19:13]	<= idata[6:0];
									3:	AddressTmp[26:20] 	<= idata[6:0];
								endcase

							end else begin
							
								case(read_cnt)
									0:	if(arm_thumb) 	oAddress[6:1] 	<= idata[6:1];
										else		oAddress[7:2] 	<= idata[6:1];
	
									1:	if(arm_thumb)	oAddress[12:1] 	<= {idata[5:0],AddressTmp[5:0]};
										else		oAddress[13:2] 	<= {idata[5:0],AddressTmp[5:0]};

									2:	if(arm_thumb)	oAddress[19:1] 	<= {idata[5:0],AddressTmp[12:0]};
										else		oAddress[20:2] 	<= {idata[5:0],AddressTmp[12:0]};

									3:	if(arm_thumb)	oAddress[26:1] 	<= {idata[5:0],AddressTmp[19:0]};
										else		oAddress[27:2] 	<= {idata[5:0],AddressTmp[19:0]};	

									4:	if(idata[MODE_BIT] == H) begin	//thumb mode
											arm_thumb <= H;
											oAddress[31:1] 	<= {idata[3:0],AddressTmp[26:0]};
										end  else begin			//arm mode
											arm_thumb <= L;
											oAddress[31:1] 	<= {idata[2:0],AddressTmp[26:0],L};
										end
								endcase


							end
		endcase

	end

end




/* Read cnt Update */
always @ ( posedge iClk or negedge iRsn ) begin
	/* Reset Logic */
	if(!iRsn) begin 
		read_cnt 	<= 0;
	end
	/* Normal Operation Logic */
	else if (idataEn) begin
		if( stage  != DECODE_HEADER && 15  > read_cnt)	// Since a-sync packet can have various length [15 > read_cnt] 
			read_cnt	<= read_cnt + 1;
		else begin
			//Stage = Decoder Header & Branch addr with continue bit
			if( (idata[0] == H) && (idata[CONTINUE_BIT] == H) )
				read_cnt <= 1;
			else
				read_cnt <= 0;
		end
	end
end


/* Isbranch Update */
always @ ( posedge iClk or negedge iRsn ) begin
	/* Reset Logic */
	if(!iRsn) begin
		isbranch 			<= 	L;
	end
	else if ( idataEn ) begin
		if( stage == DECODE_HEADER ) begin
			if(idata[0] == H) //branch header 
				isbranch 	<= 	H;
			else
				isbranch	<= 	L;
		end
	end
end

/* oEn Update */
always @ ( posedge iClk or negedge iRsn ) begin
	/* Reset Logic */
	if(!iRsn) begin
		oEn		<= 	L;
	end
	/* Normal Operation Logic */
	else if ( idataEn ) begin

		if( stage == DECODE_HEADER && idata[0] == H && idata[CONTINUE_BIT] == L )	//If branch Packet & end of branch packet
				oEn 	<=	H;	
		else if ( stage == DECODE_WAYPOINT_BRANCH_PAYLOAD && idata[CONTINUE_BIT] == L && isbranch) // end of branch packet
				oEn 	<=	H;
		else
				oEn 	<=	L;
	end else begin
				oEn 	<=	L;
	end
end 


/* Debugging */
`ifdef	VERBOSE

/* Stage Update */
always @ ( posedge iClk or negedge iRsn ) begin

	/* Reset Logic */
	if(!iRsn)  begin
		$display("(%5dns) Module : Reset On! ",$time);	
	end
	/* Normal Operation Logic */
	else if (idataEn) begin

		case(stage)
			DECODE_HEADER: 
					casex(idata)
						ASYNC_HEADER	: $display("(%5dns) Module : Got ASYNC_HEADER 0x%x",$time,idata);
						ISYNC_HEADER	: $display("(%5dns) Module : Got ISYNC_HEADER 0x%x",$time,idata);
						WAYPOINT_HEADER	: $display("(%5dns) Module : Got WAPNT_HEADER 0x%x",$time,idata);
						BRANCH_HEADER	: $display("(%5dns) Module : Got BRANCH_HEADER 0x%x",$time,idata);
						TIMESTAMP_HEADER: $display("(%5dns) Module : Got TMSTMP_HEADER 0x%x",$time,idata);
						VMID_HEADER	: $display("(%5dns) Module : Got VMID_HEADER 0x%x",$time,idata);
						CONTEXTID_HEADER: $display("(%5dns) Module : Got CONTEX_HEADER 0x%x",$time,idata);
						default		: $display("(%5dns) Module : Got UNUSED_HEADER 0x%x",$time,idata);
					endcase

			DECODE_ASYNC_PAYLOAD	:	$display("(%5dns) Module : Decoding ASYNC PACK 0x%x",$time,idata);
			DECODE_ISYNC_PAYLOAD	:	$display("(%5dns) Module : Decoding ISYNC PACK 0x%x",$time,idata);
			DECODE_WAYPOINT_BRANCH_PAYLOAD:	$display("(%5dns) Module : Decoding BRANCH OR WAYPOINT PACK 0x%x",$time,idata);
			DECODE_BRANCH_EXCEPTION	:	$display("(%5dns) Module : Decoding BRANCH & WAYPT EXCP PACK 0x%x",$time,idata);
			DECODE_TIMESTAMP_PAYLOAD:	$display("(%5dns) Module : Decoding TIMESTAMP PACK 0x%x",$time,idata);
			DECODE_CONTEXTID	:	$display("(%5dns) Module : Decoding CONTEXTID PACK 0x%x",$time,idata);
			DROP_PAYLOAD		:	$display("(%5dns) Module : IGNORE PACK 0x%x",$time,idata);	
			
		endcase



	end

end
`endif





endmodule

