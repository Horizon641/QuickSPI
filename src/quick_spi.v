//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 
// Design Name: 
// Module Name: quick_spi
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: spi module with arbitrary data length up to 64 bits,
//              i.e it could send 37 or 23 or 11 bits 
// 
// Dependencies: 
// 
// Revision:
// Revision 1.0
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

`define LSB_FIRST 0
`define MSB_FIRST 1
`define LITTLE_ENDIAN 0
`define BIG_ENDIAN 1

`define MAX_DATA_WIDTH 64
`define MAX_DATA_BYTES = MAX_DATA_WIDTH / 8

module quick_spi #
(
    // slaves number
    parameter NUMBER_OF_SLAVES = 2,
	// data transfer parameters (data bus width, words quantity, e.t.c)
    parameter INCOMING_DATA_WIDTH = 8,
    parameter OUTGOING_DATA_WIDTH = 16,
	// bits and bytes order (how outgoing data is popping from buffer)
	parameter BITS_ORDER = `MSB_FIRST,
	parameter BYTES_ORDER = `LITTLE_ENDIAN,
	// extra toggles
	parameter EXTRA_WRITE_SCLK_TOGGLES = 6,
    parameter EXTRA_READ_SCLK_TOGGLES = 4,
	// clock polarity and phase
    parameter CPOL = 0,
    parameter CPHA = 0,
	// idle values
    parameter MOSI_IDLE_VALUE = 1'b0
)
(
    input wire clk,
    input wire reset_n,
    input wire enable,
    input wire start_transaction,
    input wire[NUMBER_OF_SLAVES-1:0] slave,
    input wire operation,
    output reg end_of_transaction,
    output reg[INCOMING_DATA_WIDTH-1:0] incoming_data,
    input wire[OUTGOING_DATA_WIDTH-1:0] outgoing_data,
    output reg mosi,
    input wire miso,
    output reg sclk,
    output reg[NUMBER_OF_SLAVES-1:0] ss_n);

localparam READ = 1'b0;
localparam WRITE = 1'b1;

localparam READ_SCLK_TOGGLES = (INCOMING_DATA_WIDTH * 2) + 2;
localparam ALL_READ_TOGGLES = EXTRA_READ_SCLK_TOGGLES + READ_SCLK_TOGGLES;

// at least 1, because we could transfer i.e. 6 or 5 bits ()
localparam NUMBER_OF_FULL_BYTES = OUTGOING_DATA_WIDTH > 1 ? (OUTGOING_DATA_WIDTH / 8) : 0;
localparam NUMBER_OF_PARTICULAR_BITS = OUTGOING_DATA_WIDTH > (NUMBER_OF_FULL_BYTES * 8) ? 1 : 0;
localparam NUMBER_OF_BYTES = NUMBER_OF_FULL_BYTES + NUMBER_OF_PARTICULAR_BITS;
localparam MAX_BYTES_INDEX = NUMBER_OF_BYTES - 1;

integer sclk_toggle_count;
integer transaction_toggles;

reg spi_clock_phase;
reg[1:0] state;
//reg[7:0] byte_counter;

localparam IDLE = 2'b00;
localparam ACTIVE = 2'b01;
localparam WAIT = 2'b10;

//reg[INCOMING_DATA_WIDTH - 1:0] int_outgoing_data_buffer;
reg[INCOMING_DATA_WIDTH - 1:0] incoming_data_buffer;
reg[OUTGOING_DATA_WIDTH - 1:0] outgoing_data_buffer;
    
always @ (posedge clk) 
begin
    if(!reset_n) 
	begin
        end_of_transaction <= 1'b0;
        mosi <= MOSI_IDLE_VALUE;
        sclk <= CPOL;
        ss_n <= {NUMBER_OF_SLAVES{1'b1}};
        sclk_toggle_count <= 0;
        transaction_toggles <= 0;
        spi_clock_phase <= ~CPHA;
        incoming_data <= {INCOMING_DATA_WIDTH{1'b0}};
        incoming_data_buffer <= {INCOMING_DATA_WIDTH{1'b0}};
        outgoing_data_buffer <= {OUTGOING_DATA_WIDTH{1'b0}};
        state <= IDLE;
    end
    
    else begin
        case(state)
            IDLE: 
			begin                
                if(enable) 
				begin
                    if(start_transaction) 
					begin
					    //int_outgoing_data_buffer = outgoing_data;
                        transaction_toggles <= (operation == READ) ? ALL_READ_TOGGLES : EXTRA_WRITE_SCLK_TOGGLES;
						//for(byte_counter = 0; byte_counter < NUMBER_OF_FULL_BYTES; byte_counter = byte_counter + 1)
						outgoing_data_buffer <= put_data(outgoing_data, BYTES_ORDER);
                        state <= ACTIVE;
                    end
                end
            end
            
            ACTIVE: 
			begin
                ss_n[slave] <= 1'b0;
                spi_clock_phase <= ~spi_clock_phase;
                
                if(ss_n[slave] == 1'b0) 
				begin
                    if(sclk_toggle_count < (OUTGOING_DATA_WIDTH * 2) + transaction_toggles) 
					begin
                        sclk <= ~sclk;
                        sclk_toggle_count <= sclk_toggle_count + 1;
                    end
                end
                
                if(spi_clock_phase == 1'b0) 
				begin
                    if(operation == READ) 
					begin
                        if(sclk_toggle_count > ((OUTGOING_DATA_WIDTH * 2) + EXTRA_READ_SCLK_TOGGLES)-1) 
						begin
                            incoming_data_buffer <= incoming_data_buffer >> 1;
                            incoming_data_buffer[INCOMING_DATA_WIDTH-1] <=  miso;
                        end
                    end
                end
                
                else 
				begin 
                    if(sclk_toggle_count < (OUTGOING_DATA_WIDTH * 2) - 1)
					begin                        
                        mosi <= outgoing_data_buffer[0]; // posiibly here we are passing BITS ORDER
                        outgoing_data_buffer <= outgoing_data_buffer >> 1;
                    end
                end
                
                if(sclk_toggle_count == (OUTGOING_DATA_WIDTH * 2) + transaction_toggles) 
				begin
                    ss_n[slave] <= 1'b1;
                    mosi <= MOSI_IDLE_VALUE;
                    incoming_data <= incoming_data_buffer;
                    incoming_data_buffer <= {INCOMING_DATA_WIDTH{1'b0}};
                    outgoing_data_buffer <= {OUTGOING_DATA_WIDTH{1'b0}};
                    sclk <= CPOL;
                    spi_clock_phase <= ~CPHA;
                    sclk_toggle_count <= 0;
                    end_of_transaction <= 1'b1;
                    state <= WAIT;
                end
            end
            
            WAIT: 
			begin
                incoming_data <= {INCOMING_DATA_WIDTH{1'b0}};
                end_of_transaction <= 1'b0;
                state <= IDLE;
            end
        endcase
    end
end

function [`MAX_DATA_WIDTH - 1:0] put_data(input reg [`MAX_DATA_WIDTH - 1 : 0] data, input reg order);
begin
    //reg[7:0] shift = NUMBER_OF_BYTES - byte_number)
	if (order == `LITTLE_ENDIAN)
	begin
	     put_data = {data[63:56], data[55:48], data[47:40], data[39:32], data[31:24], data[23:16], data[15:8], data[7:0]};
	    //NUMBER_OF_BYTES - byte_number) * 8
	    /*case (byte_number)
		    0: put_data[7:0] = data[63:56];
			1: put_data[15:8] = data[55:48];
			2: put_data[23:16] = data[47:40];
			3: put_data[31:24] = data[39:32];
			4: put_data[39:32] = data[31:24];
			5: put_data[47:40] = data[23:16];	
			6: put_data[55:48] = data[15:8];
			7: put_data[63:56] = data[7:0];
			default: put_data = 0;
		endcase*/
	end
	else
	begin
	    put_data[63:0] = data[63:0];
		/*case (byte_number)
		    
		    0: put_data[7:0] = data[7:0];
			1: put_data[15:8] = data[15:8];
			2: put_data[23:16] = data[23:16];
			3: put_data[31:24] = data[31:24];
			4: put_data[39:32] = data[39:32];
			5: put_data[47:40] = data[47:40];	
			6: put_data[55:48] = data[55:48];
			7: put_data[63:56] = data[63:56];
			default: put_data = 0;
		endcase*/
	end
end
endfunction

endmodule
