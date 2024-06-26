`timescale 1ns / 1ps
  //----------------------------------------------------------------------------
`define LSB_FIRST      0
`define MSB_FIRST      1
`define LITTLE_ENDIAN  0
`define BIG_ENDIAN     1
`define MAX_DATA_WIDTH 64
  //----------------------------------------------------------------------------
module quick_spi_hard #(
  parameter NUMBER_OF_SLAVES         = 1,
  parameter INCOMING_DATA_WIDTH      = 8,
  parameter OUTGOING_DATA_WIDTH      = 16,
  parameter BITS_ORDER               = `MSB_FIRST,
  parameter BYTES_ORDER              = `BIG_ENDIAN,
  parameter EXTRA_WRITE_SCLK_TOGGLES = 0,
  parameter EXTRA_READ_SCLK_TOGGLES  = 0,
  parameter CPOL                     = 0,
  parameter CPHA                     = 1,
  parameter MOSI_IDLE_VALUE          = 1'b0
) (
  input wire                                 clk,
  input wire                                 reset_n,
  input wire                                 enable,
  input wire                                 start_transaction,
  input wire [    NUMBER_OF_SLAVES - 1 : 0 ] slave,
  input wire                                 operation,
  output reg                                 end_of_transaction,
  output reg [ INCOMING_DATA_WIDTH - 1 : 0 ] incoming_data,
  input wire [ OUTGOING_DATA_WIDTH - 1 : 0 ] outgoing_data,
  output reg                                 mosi,
  input wire                                 miso,
  output reg                                 sclk,
  output reg [    NUMBER_OF_SLAVES - 1 : 0 ] ss_n
);
  //----------------------------------------------------------------------------
  localparam READ  = 1'b0;
  localparam WRITE = 1'b1;
  //----------------------------------------------------------------------------
  localparam READ_SCLK_TOGGLES  = (INCOMING_DATA_WIDTH * 2);
  localparam WRITE_SCLK_TOGGLES = (OUTGOING_DATA_WIDTH * 2);
  localparam ALL_READ_TOGGLES   = EXTRA_READ_SCLK_TOGGLES + READ_SCLK_TOGGLES;
  localparam ALL_WRITE_TOGGLES  = EXTRA_WRITE_SCLK_TOGGLES + WRITE_SCLK_TOGGLES;
  //----------------------------------------------------------------------------
  localparam NUMBER_OF_FULL_BYTES      =  OUTGOING_DATA_WIDTH > 1  ? 
                                         (OUTGOING_DATA_WIDTH / 8) : 0;
  localparam NUMBER_OF_PARTICULAR_BITS =  OUTGOING_DATA_WIDTH > 
                                         (NUMBER_OF_FULL_BYTES * 8) ? 1 : 0;
  localparam NUMBER_OF_BYTES           = NUMBER_OF_FULL_BYTES + 
                                         NUMBER_OF_PARTICULAR_BITS;
  localparam MAX_BYTES_INDEX           = NUMBER_OF_BYTES - 1;
  //----------------------------------------------------------------------------
  integer sclk_toggle_count;
  integer transaction_toggles;
  //----------------------------------------------------------------------------
  reg spi_clock_phase;
  reg [ 1 : 0 ] state;
  //----------------------------------------------------------------------------
  localparam IDLE   = 2'b00;
  localparam ACTIVE = 2'b01;
  localparam WAIT   = 2'b10;
  //----------------------------------------------------------------------------
  reg [ INCOMING_DATA_WIDTH - 1 : 0 ] incoming_data_buffer;
  reg [ OUTGOING_DATA_WIDTH - 1 : 0 ] outgoing_data_buffer;
  reg [     `MAX_DATA_WIDTH - 1 : 0 ] intermediate_buffer;
  //----------------------------------------------------------------------------
  reg[2:0] bit_counter;
  reg[3:0] byte_counter;
  reg[5:0] counter;
  //----------------------------------------------------------------------------
  always @ (posedge clk) 
    begin
      if(!reset_n) 
        begin
          end_of_transaction   <= 1'b0;
          mosi                 <= MOSI_IDLE_VALUE;
          sclk                 <= CPOL;
          ss_n                 <= {NUMBER_OF_SLAVES{1'b1}};
          sclk_toggle_count    <= 0;
          transaction_toggles  <= 0;
          spi_clock_phase      <= ~CPHA;
          incoming_data        <= {INCOMING_DATA_WIDTH{1'b0}};
          incoming_data_buffer <= {INCOMING_DATA_WIDTH{1'b0}};
          outgoing_data_buffer <= {OUTGOING_DATA_WIDTH{1'b0}};
          state                <= IDLE;
          bit_counter          <= 0;
          byte_counter         <= 0;
          counter              <= 0;
        end
      else
        begin
          case(state)
            IDLE:
              begin
                if(enable)
                  begin
                    bit_counter <= 0;
                    byte_counter <= 0;
                    if(start_transaction) 
                      begin
                        transaction_toggles <= (operation == READ) ? ALL_READ_TOGGLES : ALL_WRITE_TOGGLES;
                        intermediate_buffer = put_data(outgoing_data, BYTES_ORDER);
                        outgoing_data_buffer <= intermediate_buffer[15:0];
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
                    if(sclk_toggle_count < transaction_toggles) 
                      begin
                        sclk <= ~sclk;
                        sclk_toggle_count <= sclk_toggle_count + 1;
                      end
                  end
                if(spi_clock_phase == 1'b0)
                  begin
                    if(operation == READ)
                       begin
                         incoming_data_buffer <= incoming_data_buffer >> 1;
                         incoming_data_buffer[INCOMING_DATA_WIDTH-1] <=  miso;
                       end
                  end
                else 
                  begin 
                    if(operation == WRITE)
                      begin
                        if(BITS_ORDER == `LSB_FIRST)
                          begin
                            mosi <= outgoing_data_buffer[0];
                            outgoing_data_buffer <= outgoing_data_buffer >> 1;
                          end
                        else
                          begin
                            bit_counter <= bit_counter + 1;
                            mosi <= outgoing_data_buffer[7 - bit_counter];
                            if(bit_counter == 7)
                              outgoing_data_buffer <= outgoing_data_buffer >> 8;
                          end
                      end
                  end
                if(sclk_toggle_count == transaction_toggles) 
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
                counter <= counter + 1;
                end_of_transaction <= 1'b0;
                if (counter == 50)
                  begin
                    incoming_data <= {INCOMING_DATA_WIDTH{1'b0}};
                    state <= IDLE;
                    counter <= 0;
                  end
              end
          endcase
      end
  end

function [`MAX_DATA_WIDTH - 1:0] put_data(input reg [`MAX_DATA_WIDTH - 1 : 0] data, input reg order);
    reg [`MAX_DATA_WIDTH - 1:0] result;
    reg[7:0] shift;   
begin
    shift = `MAX_DATA_WIDTH - NUMBER_OF_BYTES * 8;
	if (order == `BIG_ENDIAN)//`LITTLE_ENDIAN)
	begin
	      result = {data[7:0], data[15:8], data[23:16], data[31:24], data[39:32], data[47:40], data[55:48], data[63:56]};    
		 if(shift > 0)
		     put_data = result >> shift;
		     //put_data[NUMBER_OF_BYTES * 8 - 1 : 0] = result[`MAX_DATA_WIDTH - 1 : `MAX_DATA_WIDTH - NUMBER_OF_BYTES * 8];
		 else put_data = result;
	end
	else if (order == `LITTLE_ENDIAN)//`BIG_ENDIAN)
	begin
	    put_data = data;
	end
end
endfunction

endmodule
