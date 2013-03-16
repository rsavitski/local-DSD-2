module testbench();


reg clk = 0;
reg reset = 1;

reg [5:0] mxsize;
reg dma_done;
reg [9:0] dma_matrix_addr = 2;
reg [31:0] dma_matrix_data = 3;
reg dma_matrix_we = 0;

reg [31:0] result;

reg start_dma_pulse;
////////////////////////////////////////////////////
initial
#30 reset = 0;

always
#5 clk = !clk;

initial
begin
	#40 start_dma_pulse = 0;
	#45 start_dma_pulse = 1;
	#50 start_dma_pulse = 0;
end

initial 
begin
	#0 dma_done = 0;
	#150 dma_done = 1;


end

initial
begin
	#0 mxsize = 3;
end


//========================================================================================

localparam DIV_LATENCY = 14;
localparam MUL_LATENCY = 5;
localparam SUB_LATENCY = 8;

////////////////////////////////////////////////////
//glue
reg [5:0] MXSIZE;

always @(*)
begin
	MXSIZE <= mxsize;
end

////////////////////////////////////////////////////
reg [5:0] current_mxsize; //TODO: 32x32 hardcode
reg [5:0] current_mxsize_r;

reg update_current_mxsize;

reg [31:0] alpha_value; 

reg [31:0] left_col [0:30]; //preloaded column of things to divide //TODO: hardcoded for 32x32 max // [0:MAX_MX_SIZE-2] since N-1 at top iteration
reg [31:0] top_row [0:30]; // preloaded top row with N-1 valid elements (size N-1) //TODO: hardcoded for 32x32 max


reg reset_pipe;

reg div_enable;
reg get_next_coefficient;


reg pipe_done_at_edge;


reg dmul_done_next_cycle;

////////////////////////////////////////////////////
reg [31:0] mul_input_2; // top row coefficients go here

reg [31:0] coefficient_dividend; // TODO: DIVIDEND


wire [31:0] mxram_data_out_a;
wire [31:0] mxram_data_out_b;
////////////////////////////////////////////////////
////////////////////////////////////////////////////

reg [31:0] diag_mul_in1;
reg [31:0] diag_mul_in2;
wire [31:0] diag_mul_out;
////////////////////////////////////////////////////
////////////////////////////////////////////////////

wire [31:0] div_out;
wire [31:0] mul_out;
wire [31:0] sub_out;


reg [31:0] div_in1;
reg [31:0] div_in2;
reg [31:0] mul_in1;
reg [31:0] mul_in2;
reg [31:0] sub_in1;
reg [31:0] sub_in2;



integer i;
/*
//reg [31:0] div_dummy [0:DIV_LATENCY-1];
//reg [31:0] mul_dummy [0:MUL_LATENCY-1];
reg [31:0] sub_dummy [0:SUB_LATENCY-1];

always @(posedge clk) begin

	if (!reset) begin

	//if (div_enable) begin
	//	for (i=0; i<DIV_LATENCY; i = i+1) begin
	//		div_dummy[i+1] <= div_dummy[i];
	//	end
	//	div_dummy[0] <= div_in1 / div_in2;
	//end


	//for (i=0; i<MUL_LATENCY; i = i+1) begin
	//	mul_dummy[i+1] <= mul_dummy[i];
	//end
	//mul_dummy[0] <= mul_in1 * mul_in2;

	for (i=0; i<SUB_LATENCY; i = i+1) begin
		sub_dummy[i+1] <= sub_dummy[i];
	end
	sub_dummy[0] <= sub_in1-sub_in2;

	end

end*/

//assign div_out = div_dummy[DIV_LATENCY-1];
//assign mul_out = mul_dummy[MUL_LATENCY-1];
//assign sub_out = sub_dummy[SUB_LATENCY-1];


always @(*)
begin
	div_in1 <= coefficient_dividend;
	div_in2 <= alpha_value;

	mul_in1 <= div_out;
	mul_in2 <= mul_input_2;

	sub_in1 <= mxram_data_out_a;
	sub_in2 <= mul_out;
end

////////////////////////////////////////////////////
////////////////////////////////////////////////////


fp_div1	fp_div1_inst (
	.clk_en ( div_enable ),
	.clock ( clk ),
	.dataa ( div_in1 ),
	.datab ( div_in2 ),
	.result ( div_out )
	);

fp_mul1	fp_mul1_inst (
	.clock ( clk ),
	.dataa ( mul_in1 ),
	.datab ( mul_in2 ),
	.result ( mul_out )
	);

fp_sub1	fp_sub1_inst (
	.clock ( clk ),
	.dataa ( sub_in1 ),
	.datab ( sub_in2 ),
	.result ( sub_out )
	);



////////////////////////////////////////////////////
////////////////////////////////////////////////////

localparam idle_state = 0;
localparam algo_setup_state = 1;
localparam iteration_setup_state = 2;
localparam rotation_state = 3;
localparam preload_rowcol_state = 4;
localparam dummy_cycle = 5;
localparam pipeline_state = 6;
localparam calc_diagonal_state = 7;
localparam doolittle_singular_state = 8;
localparam doolittle_done_state = 9;
localparam TODO_DONE = 10;
localparam TODO_DEAD = 11;

reg [3:0] fsm_state;



////////////////////////////////////////////////////

reg [9:0] rot_alpha_addr;

reg [9:0] preload_row_addr;
reg [9:0] preload_col_addr;

reg [9:0] readmx_addr;
reg [9:0] writemx_addr;

reg [9:0] diag_addr;


reg writemx_wen;
////////////////////////////////////////////////////

reg [9:0] mxram_addr_a;
reg [9:0] mxram_addr_b;

reg [31:0] mxram_data_in_a;
reg [31:0] mxram_data_in_b;

reg mxram_wen_a;
reg mxram_wen_b;



matrixram	matrixram_inst (
	.address_a ( mxram_addr_a ),
	.address_b ( mxram_addr_b ),
	.clock ( clk ),
	.data_a ( mxram_data_in_a ),
	.data_b ( mxram_data_in_b ),
	.wren_a ( mxram_wen_a ),
	.wren_b ( mxram_wen_b ),
	.q_a ( mxram_data_out_a ),
	.q_b ( mxram_data_out_b )
	);


always @(*) begin

	mxram_addr_a <= 0;
	mxram_addr_b <= 0;

	mxram_data_in_a <= 0;
	mxram_data_in_b <= 0;

	mxram_wen_a <= 0;
	mxram_wen_b <= 0;

	if (!dma_done) begin // dma owns ram

		mxram_addr_a <= dma_matrix_addr;
		mxram_data_in_a <= dma_matrix_data;
		mxram_wen_a <= dma_matrix_we;

	end 
	else begin //TODO: case state etc
		
		if (fsm_state == iteration_setup_state || fsm_state == rotation_state) begin 
			mxram_addr_a <= rot_alpha_addr;
		end
		else if (fsm_state == preload_rowcol_state) begin

			mxram_addr_a <= preload_row_addr;
			mxram_addr_b <= preload_col_addr;

		end
		else if (fsm_state == pipeline_state) begin

			mxram_addr_a <= readmx_addr;
			mxram_addr_b <= writemx_addr;

			mxram_data_in_b <= sub_out;
			mxram_wen_b <= writemx_wen; //SEVERE, better to derive a signal
		
		end			
		else if (fsm_state == calc_diagonal_state) begin

			mxram_addr_a <= diag_addr;
		

		end
	end	

end

////////////////////////////////////////////////////

reg [9:0] rowptr [0:31]; //TODO: hardcoded for 32x32
reg rotate;
reg reset_rowptr;

integer v;

always @(posedge clk) begin

	if (reset || reset_rowptr) begin

		// initialise to non-rotated state
		for (v=0; v<32; v=v+1) begin
			rowptr[v] = (32*v);
		end 
	end
	else begin

		if (rotate) begin

			rowptr[MXSIZE-current_mxsize] <= rowptr[MXSIZE-1];

			for (v=1; v<32; v=v+1) begin
				if ((v >= MXSIZE-current_mxsize+1) && (v < MXSIZE)) begin

					rowptr[v] <= rowptr[v-1];

				end
			end
		end
	end
end


////////////////////////////////////////////////////
reg det_instr_pending;

reg alpha_dead_read_cycle;

reg [4:0] rot_cnt; //TODO: hardcoded for 32x32
reg [5:0] rc_cnt; //needs extra bit

reg nop_rc_done;

reg p_sign;

reg det_done_pulse;

// master registered process of doing everything
always @(posedge clk) begin

	reset_rowptr <= 0;
	alpha_dead_read_cycle <= 0;
	det_done_pulse <= 0;

	if (reset) begin

		fsm_state <= idle_state;

		p_sign <= 0;
		reset_rowptr <= 0;
		alpha_value <= 0;
		alpha_dead_read_cycle <= 0;
		rot_cnt <= 0;
		rc_cnt <= 0;
		nop_rc_done <= 0;
		det_done_pulse <= 0;

	end
	else begin

		case (fsm_state)

			idle_state: 
			begin
				if (dma_done && det_instr_pending) begin
					fsm_state <= algo_setup_state;

					reset_rowptr <= 1; // clocked so cycle delay introduced

				end
			end

			algo_setup_state:
			begin
				p_sign <= 0;

				fsm_state <= rotation_state;

			end

			iteration_setup_state: //note current mxsize updated combinatorially below
			begin
				alpha_dead_read_cycle <= 0;
				alpha_value <= 0;
				rot_cnt <= 0;
				rc_cnt <= 0;
				nop_rc_done <= 0;

				if (current_mxsize == 1) begin //TODO: SEVERE: termination goes here, check C block for correct const
					fsm_state <= calc_diagonal_state;
				end
				else begin
					fsm_state <= rotation_state;
				end
			end

			rotation_state:
			begin
				alpha_dead_read_cycle <= ~alpha_dead_read_cycle;

				if (alpha_dead_read_cycle == 0) begin
					// if alpha nonzero, proceed to next state and save it in the reg
					if (mxram_data_out_a != 0) begin

						fsm_state <= preload_rowcol_state;
						alpha_value <= mxram_data_out_a;

					end
					else begin

						rot_cnt <= rot_cnt + 1;
						p_sign <= ~p_sign;
						if (rot_cnt == current_mxsize-1) begin
							fsm_state <= doolittle_singular_state; //singular as the rotations have been exhausted
						end

					end
				end
				

				
			end

			preload_rowcol_state:
			begin

				rc_cnt <= rc_cnt + 1;

				if (nop_rc_done == 0) begin
					nop_rc_done <= 1;
				end
				else begin
					
					if (rc_cnt == current_mxsize-1) begin
						fsm_state <= dummy_cycle;
					end

					top_row[rc_cnt-1] <= mxram_data_out_a;

					left_col[rc_cnt-1] <= mxram_data_out_b;

				end
			end

			dummy_cycle: //hack hack hack :|
			begin
				fsm_state <= pipeline_state;
			end

			pipeline_state:
			begin
				if (pipe_done_at_edge) begin
					fsm_state <= iteration_setup_state;
				end
			end

			calc_diagonal_state:
			begin
					if (dmul_done_next_cycle) begin
						fsm_state <= doolittle_done_state; 
					end
			end

			doolittle_done_state:
			begin
				det_done_pulse <= 1;
				fsm_state <= idle_state;

			end

			doolittle_singular_state:
			begin
				det_done_pulse <= 1;
				fsm_state <= idle_state;
			end


			default:;

		endcase

	end

end


////////////////////////////////////////////////////
// interfacing


always @(posedge clk) begin
	if (start_dma_pulse)
		det_instr_pending <= 1;
	else if (fsm_state == doolittle_done_state || fsm_state == doolittle_singular_state)
		det_instr_pending <= 0;
end


////////////////////////////////////////////////////////////////////////////////////////////////////////
always @(posedge clk) begin
	if (reset)
		result <= 0;
	else if (dmul_done_next_cycle)
		result <= {p_sign ^ diag_mul_out[31],diag_mul_out[30:0]};
	else if (fsm_state == doolittle_singular_state)
		result <= -1;

end
////////////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////
always @(*) begin

	rot_alpha_addr <= rowptr[MXSIZE-current_mxsize] + MXSIZE-current_mxsize;

end

/////////////////////////////////////////////////////////////
// current mxsize reg

always @(posedge clk) begin

	if (reset) begin

		current_mxsize_r <= 0;

	end
	else begin

		if (update_current_mxsize) begin

			current_mxsize_r <= current_mxsize;

		end
	end
end

always @(*) begin

	update_current_mxsize <= 0;

	current_mxsize <= current_mxsize_r;

	case (fsm_state)

		algo_setup_state:
		begin
			update_current_mxsize <= 1;
			current_mxsize <= MXSIZE;
		end

		iteration_setup_state: 
		begin
			update_current_mxsize <= 1;
			current_mxsize <= current_mxsize_r-1;
		end

		default:;

	endcase
end


/////////////////////////////////////////////////////////////
always @(*) begin
	rotate <= 0;

	if (fsm_state == rotation_state && mxram_data_out_a == 0 && alpha_dead_read_cycle == 0) begin

		rotate <= 1;

	end
end

/////////////////////////////////////////////////////////////
// preload state address setup
always @(*) begin

	preload_row_addr <= rowptr[MXSIZE-current_mxsize] + MXSIZE-current_mxsize+rc_cnt+1;
	preload_col_addr <= rowptr[MXSIZE-current_mxsize+rc_cnt+1] + MXSIZE-current_mxsize;

end

/////////////////////////////////////////////////////////////
// processing pipe's reset
always @(*) begin

	reset_pipe <= 1;

	if (fsm_state == pipeline_state) begin

		reset_pipe <= 0;

	end

end




//========================================================================================
//========================================================================================
//========================================================================================
//========================================================================================
//========================================================================================
//========================================================================================
////////////////////////////////////////////////////


reg div_saturated;

reg [4:0] div_cnt; //TODO: hardcoded for 32x32 max
reg [5:0] div_sat_cnt; //TODO: hardcoded for 32x32 max


// coefficient normalisation (div stage)

always @(posedge clk) begin

	if (reset_pipe || reset) begin
		div_cnt <= 0;
		div_sat_cnt <= 0;
		coefficient_dividend <= left_col[div_cnt];

		div_saturated <= 0;
	end
	else begin

		div_cnt <= div_cnt + 1;

		if (div_cnt == MXSIZE-1) begin //specific wraparound point doesn't matter as the latter stages will consume only the valid coefficients, only N-1 values are actually used
			div_cnt <= 0;
		end

		// push value into division block
		coefficient_dividend <= left_col[div_cnt+1];

		// count until division stage is saturated and has the first value at the output of the division block
		div_sat_cnt <= div_sat_cnt + 1;

		if (div_sat_cnt == DIV_LATENCY-1) begin
			div_saturated <= 1;

			div_sat_cnt <= DIV_LATENCY-1; // doesn't matter what happens to it after here, can increment forever
		end

	end
end

// div funit clk_en
always @(*) begin

	div_enable <= 1;

	if (div_saturated == 1) begin
		div_enable <= get_next_coefficient;
	end
end

//========================================================================================




reg [4:0] mul_cnt;
reg [5:0] mul_sat_cnt;

reg mul_saturated_next_cycle;

// multiplier fsm stage
// NB: works down to 2x2 size
always @(posedge clk) begin

	if (reset_pipe || reset) begin

		mul_cnt = 0;
		mul_sat_cnt <= 0;
		mul_input_2 <= top_row[mul_cnt];

		mul_saturated_next_cycle <= 0;

	end//////////////////////////////////////////////////
	else if (div_saturated) begin

		// wrapping iteration over first row
		mul_cnt = mul_cnt + 1;
		if (mul_cnt == current_mxsize-1) begin // -2 since we do an N-1 length sweep
			mul_cnt = 0;
		end

		// put into multiplication by normalised coefficient pipeline
		mul_input_2 <= top_row[mul_cnt];

		// upcount for multiplication latency
		mul_sat_cnt <= mul_sat_cnt + 1;
		if (mul_sat_cnt == MUL_LATENCY-2) begin //-1 for proper saturation, properly hacked here
			mul_saturated_next_cycle <= 1; // doesn't matter what happens to mul_sat_cnt after this
			mul_sat_cnt <= MUL_LATENCY-1;
		end

	end
end

always @(*) begin

	get_next_coefficient <= 0; // enable signal for div stage to give next coefficient

	if (mul_cnt == current_mxsize-2) begin // enable div pipeline to get next coefficient for next row
		get_next_coefficient <= 1;
	end

end




//========================================================================================

reg [4:0] i_read; //TODO: hardcoded for 32x32
reg [4:0] j_read; //TODO: hardcoded for 32x32

reg sub_saturated;
reg [4:0] sub_sat_cnt;


// third block, substractor

always @(posedge clk) begin

	if (reset || reset_pipe) begin

		i_read <= MXSIZE-current_mxsize+1; // ends at MXSIZE-1 always
		j_read <= MXSIZE-current_mxsize+1; // ends at MXSIZE-1 always

		sub_saturated <= 0;
		sub_sat_cnt	<= 0;


	end

	else if (mul_saturated_next_cycle) begin // pipeline before this stage fully saturated

		// for i, for j, read all N-1 x N-1 matrix elements row by row
		i_read <= i_read + 1;

		j_read <= j_read;

		if (i_read == MXSIZE-1) begin
			i_read <= MXSIZE-current_mxsize+1;
			j_read <= j_read +1 ;
		end


		//SEVERE: off by 1 and blocking


		 if (i_read == MXSIZE-1 && j_read == MXSIZE-1) begin 
		 	j_read <= MXSIZE-current_mxsize+1; // doesn't matter
		 end




		sub_sat_cnt <= sub_sat_cnt +1;

		if (sub_sat_cnt == SUB_LATENCY) begin // -1+1 due to presub coming from mul stage
			sub_saturated <= 1; // doesn't matter what happens to sub_sat_cnt after this
			sub_sat_cnt <= SUB_LATENCY-1;
		end



		// q_a <= ij_to_address(i,j);

	end


end


always @(*) begin
	readmx_addr <= rowptr[j_read] + i_read;
end

//========================================================================================

reg mx_iterate_done; //TODO: transition out of state is together with mx_terate_done (combinatorially), last write happening on the egde mx_iterate_done toggles
reg [4:0] i_write; //TODO: hardcoded for 32x32
reg [4:0] j_write; //TODO: hardcoded for 32x32


// write to mem block

always @(posedge clk) begin

	if (reset || reset_pipe) begin

		i_write <= MXSIZE-current_mxsize+1; // ends at MXSIZE-1 always
		j_write <= MXSIZE-current_mxsize+1; // ends at MXSIZE-1 always
		mx_iterate_done <= 0;

	end

	else if (sub_saturated) begin // pipeline before this stage fully saturated

		// for i, for j, read all N-1 x N-1 matrix elements row by row
		i_write <= i_write + 1;

		j_write <= j_write;

		if (i_write == MXSIZE-1) begin
			i_write <= MXSIZE-current_mxsize+1;
			j_write <= j_write +1 ;
		end



		 if (i_write == MXSIZE-1 && j_write == MXSIZE-1) begin 
		 	mx_iterate_done <= 1;//sub sweep done
		 	j_write <= MXSIZE-current_mxsize+1; // doesn't matter
		 end

		 //data [i+1] // USE BLOCKING

		// q_a <= ij_to_address(i,j);

	end


end


always @(*) begin
	writemx_addr <= rowptr[j_write] + i_write;
end


always @(*) begin

	writemx_wen <= 0;

	if (sub_saturated == 1 && !mx_iterate_done) begin
		writemx_wen <= 1;
	end

end

always @(*) begin

	pipe_done_at_edge <= 0;

	 if (i_write == MXSIZE-1 && j_write == MXSIZE-1 && sub_saturated) begin 
	 	pipe_done_at_edge <= 1;
	 end
end

////////////////////////////////////////////////////////////////////////////////
// Calculate the result



reg [31:0] diag_mul_out_reg;

reg [5:0] diag_index;
reg [4:0] diag_mul_delay_cnt;

reg diag_init_cycle_done;

//////////////////////////////////////////////////// SIMSIMSIM
////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////
reg [31:0] dmul_in1;
reg [31:0] dmul_in2;
/*
reg [31:0] dmul_dummy [0:MUL_LATENCY-1];

always @(posedge clk) begin

	if (!reset) begin

		for (i=0; i<MUL_LATENCY; i = i+1) begin
			dmul_dummy[i+1] <= dmul_dummy[i];
		end
		dmul_dummy[0] <= dmul_in1 * dmul_in2;
	end

end

assign diag_mul_out = dmul_dummy[MUL_LATENCY-1];*/


always @(*)
begin

	dmul_in1 <= diag_mul_in1;
	dmul_in2 <= diag_mul_in2;

end

////////////////////////////////////////////////////

fp_mul1	fp_mul1_inst_2 (
	.clock ( clk ),
	.dataa ( dmul_in1 ),
	.datab ( dmul_in2 ),
	.result ( diag_mul_out )
	);


////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////


always @(posedge clk) begin

	if (reset || fsm_state != calc_diagonal_state) begin //reset/defaults

		diag_mul_delay_cnt <= 0;
		diag_index <= 0;

		
		diag_init_cycle_done <= 0;

	end
	else begin

		if (diag_init_cycle_done == 0) 
			diag_init_cycle_done <= 1;
		else begin

			diag_mul_delay_cnt <= diag_mul_delay_cnt + 1;
			if (diag_mul_delay_cnt == MUL_LATENCY-1) begin //-1+1???
				diag_mul_delay_cnt <= 0;
			end

			if (diag_mul_delay_cnt == 0) begin
				diag_index <= diag_index + 1; //blocking

			end
		end
	end
end

always @(posedge clk) begin
	if (reset || fsm_state != calc_diagonal_state) begin
		diag_mul_out_reg <= 0;
	end
	else begin
		diag_mul_out_reg <= diag_mul_out;
	end
end


always @(*) begin

	diag_mul_in1 <= 0;

	if (diag_mul_delay_cnt == 0) begin
		diag_mul_in1 <= mxram_data_out_a;
	end
end

always @(*) begin
	diag_addr <= rowptr[diag_index] + diag_index;
end


always @(*) begin
	diag_mul_in2 <= 0;

	if (diag_mul_delay_cnt == 0) begin

		if (diag_index == 0)
			diag_mul_in2 <= 32'h3f800000; //SEVERE: FP 1
		else begin
			diag_mul_in2 <= diag_mul_out;
		end

	end
end

always @(*) begin

	dmul_done_next_cycle <= 0;

	if (diag_mul_delay_cnt == 0 && diag_index == MXSIZE) begin
		dmul_done_next_cycle <= 1;
	end

end

////////////////////////////////////////////////////


endmodule