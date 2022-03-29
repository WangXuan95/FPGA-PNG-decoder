
//--------------------------------------------------------------------------------------------------------
// Module  : huffman_decoder
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
//--------------------------------------------------------------------------------------------------------

module huffman_decoder #(
    parameter    NUMCODES = 288,
    parameter    OUTWIDTH = 10
)(
    rstn, clk,
    inew, ien, ibit,
    oen, ocode,
    rdaddr, rddata
);

function automatic integer clogb2(input integer val);
    integer valtmp;
    valtmp = val;
    for(clogb2=0; valtmp>0; clogb2=clogb2+1) valtmp = valtmp>>1;
endfunction

input                               rstn, clk;
input                               inew, ien, ibit;
output                              oen;
output  [            OUTWIDTH-1:0]  ocode;
output  [clogb2(2*NUMCODES-1)-1:0]  rdaddr;
input   [            OUTWIDTH-1:0]  rddata;

wire                              rstn, clk;
wire                              inew, ien, ibit;
reg                               oen = 1'b0;
reg  [            OUTWIDTH-1:0]   ocode = '0;
wire [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
wire [            OUTWIDTH-1:0]   rddata;

reg  [clogb2(2*NUMCODES-1)-2:0]   tpos = '0;
wire [clogb2(2*NUMCODES-1)-2:0]   ntpos;
reg                               ienl = 1'b0;

assign rdaddr = {ntpos, ibit};

assign ntpos = ienl ? (clogb2(2*NUMCODES-1)-1)'(rddata<(OUTWIDTH)'(NUMCODES) ? '0 : rddata-(OUTWIDTH)'(NUMCODES)) : tpos;

always @ (posedge clk or negedge rstn)
    if(~rstn)
        ienl <= '0;
    else
        ienl <= inew ? '0 : ien;

always @ (posedge clk or negedge rstn)
    if(~rstn)
        tpos <= '0;
    else
        tpos <= inew ? '0 : ntpos;

always_comb
    if(ienl && rddata<NUMCODES) begin
        oen   = 1'b1;
        ocode = rddata;
    end else begin
        oen   = 1'b0;
        ocode = '0;
    end

endmodule
