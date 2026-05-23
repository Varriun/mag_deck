module uart_tx(
  input logic       clk,
  input logic       rst_n,

  input logic       tx_start,
  input logic [7:0] tx_byte,

  output logic      tx_pin,
  output logic      tx_busy
);

typedef enum logic [1:0] {IDLE, START, DATA,STOP} state_t;
state_t state;

logic [3:0] bit_cnt;
logic [8:0] baud_cnt;

localparam CLK_FREQ = 50_000_000;
localparam BAUD_RATE = 115_200;
localparam DIVISOR = CLK_FREQ/BAUD_RATE;

always_ff @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
    tx_busy   <= 1'b0;
    tx_pin    <= 1'b1;
    bit_cnt   <= 1'b0;
    baud_cnt  <= 1'b0;
    state <= IDLE;
  end else begin
      case (state)
        START: begin
          //NOTE: needs to output a start bit, which is... 0?
          tx_pin <= 1'b0;
          if (baud_cnt == DIVISOR -1) begin
           state    <= DATA;
           baud_cnt <= 1'b0;
         end else begin
           baud_cnt++;
         end
        end
        DATA: begin
          tx_pin <= tx_byte[bit_cnt];
          if (baud_cnt == DIVISOR -1) begin
            baud_cnt <= 1'b0;
            if (bit_cnt == 7) begin
              state    <= STOP;
              bit_cnt  <= 1'b0; 
            end else begin
              bit_cnt++;
            end
          end else begin
            baud_cnt++;
          end
        end
        STOP: begin
          tx_pin <= 1'b1;
          if(baud_cnt == DIVISOR -1) begin
            baud_cnt <= 1'b0;
            tx_busy  <= 1'b0;
            state    <= IDLE;
          end else begin
            baud_cnt++;
          end
        end
        default : begin
          /*NOTE: once again, IDLE is technically my default state*/
          if (tx_start) begin
            tx_busy   <= 1'b1;
            bit_cnt   <= 1'b0;
            baud_cnt  <= 1'b0;
            state <= START;
          end
        end
      endcase
  end
end
endmodule
