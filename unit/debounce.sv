module debounce #(
    parameter THRESHOLD = 50000
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sw_in,
    output logic sw_out
);

    logic [18:0] counter;
    logic sync_0, sync_1;

    // ──────────────────────────────────────────────────────────────
    // Single always_ff block handles BOTH synchronisation and debounce.
    //
    // Why one block?
    //   Having two separate always_ff blocks that both assign sync_0
    //   and sync_1 creates a "multiple driver" conflict — the simulator
    //   can't resolve which block "wins", producing X (undefined) values.
    //
    // What this block does:
    //   1. RESET  — forces all regs to 0 so GTKWave starts clean (no red X).
    //   2. SYNC   — double-flop (sync_0 → sync_1) samples sw_in into the
    //               clock domain, preventing metastability.
    //   3. DEBOUNCE — compares the stable synced value (sync_1) against the
    //               last confirmed output (sw_out). If they differ, a counter
    //               counts up; only when it reaches THRESHOLD is sw_out updated.
    //               Any glitch resets the counter back to 0.
    // ──────────────────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0  <= 1'b0;
            sync_1  <= 1'b0;
            sw_out  <= 1'b0;
            counter <= 19'd0;
        end else begin
            // Stage 1: synchronise raw input into clock domain
            sync_0 <= sw_in;
            sync_1 <= sync_0;

            // Stage 2: debounce — only update output after stable for THRESHOLD cycles
            if (sync_1 != sw_out) begin
                if (counter < THRESHOLD) begin
                    counter <= counter + 1'b1;
                end else begin
                    sw_out  <= sync_1;
                    counter <= 19'd0;
                end
            end else begin
                counter <= 19'd0;   // input matches output — reset counter
            end
        end
    end

endmodule
