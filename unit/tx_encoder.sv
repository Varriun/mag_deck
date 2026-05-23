module tx_encoder (
  input  logic        clk,
  input  logic        rst_n,

  // From input_mapper — 5-byte packet, valid for the full clock cycle pkt_valid is high
  input  logic [7:0]  pkt [0:4],
  input  logic        pkt_valid,

  // To uart_tx
  output logic [7:0]  tx_byte,   // byte currently being sent
  output logic        tx_start,  // one-cycle pulse: tells uart_tx to begin transmitting
  input  logic        tx_busy    // uart_tx holds this high while a byte is in flight
);

  // ── State machine ─────────────────────────────────────────────────────────
  //
  // This module is a sequencer: it walks through pkt[0..4] and hands each
  // byte to uart_tx one at a time, waiting for the previous byte to finish
  // before starting the next.
  //
  // Three states are enough:
  //   IDLE    — waiting for pkt_valid to arrive
  //   START   — assert tx_start for one cycle, then step into WAIT
  //   WAIT    — hold until tx_busy goes low; either send next byte or go IDLE

  typedef enum logic [1:0] {IDLE, START,WAIT} state_t;
  state_t state;

  // ── Packet latch ──────────────────────────────────────────────────────────
  //
  // You cannot read pkt[] directly in the slow serialisation loop — input_mapper
  // may update it on the next poll_tick while you are still sending the current
  // one. Capture a private copy on the cycle pkt_valid fires, then work from
  // that copy.
  //
  // Hint: logic [7:0] buf [0:4]; — same shape as the input port.

  logic [7:0] pkt_latch [0:4];

  // ── Byte counter ──────────────────────────────────────────────────────────
  //
  // Need to track which byte you are currently sending (0 through 4).
  // A 3-bit counter is more than enough for 5 values.

  logic [3:0] byte_idx;

  // ── State machine body ────────────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      byte_idx  <= 1'b0;
      tx_start  <= 1'b0;
      tx_byte   <= 1'b0;
      state     <= IDLE;
    end else begin
      case (state)
        START: begin
          tx_start <= 1'b1; 
          tx_byte <= pkt_latch[byte_idx];
          state <= WAIT;
        end
        WAIT: begin
          tx_start <= 1'b0;
          if (!tx_busy && !tx_start) begin
            if (byte_idx == 4) begin
              state <= IDLE;
            end else begin
              byte_idx++;
              state <= START;
            end
          end
        end
        default: begin 
        /*NOTE: IDLE is techincally a default state of things*/
          if (pkt_valid) begin
            pkt_latch[0] <= pkt[0];
            pkt_latch[1] <= pkt[1];
            pkt_latch[2] <= pkt[2];
            pkt_latch[3] <= pkt[3];
            pkt_latch[4] <= pkt[4];
            byte_idx <= 1'b0;
            state <= START;
          end
        end
      endcase
    end
  end

endmodule
