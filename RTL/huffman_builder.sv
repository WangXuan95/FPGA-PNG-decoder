
//--------------------------------------------------------------------------------------------------------
// Module  : huffman_builder
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
//--------------------------------------------------------------------------------------------------------

module huffman_builder #(
    parameter NUMCODES = 288,
    parameter CODEBITS = 5,
    parameter BITLENGTH= 15,
    parameter OUTWIDTH = 10
) (
    rstn, clk,
    wren, wraddr, wrdata,
    run , done,
    rdaddr, rddata
);

function automatic integer clogb2(input integer val);
    integer valtmp;
    valtmp = val;
    for(clogb2=0; valtmp>0; clogb2=clogb2+1) valtmp = valtmp>>1;
endfunction

input                               rstn;
input                               clk;
input                               wren;
input  [  clogb2(NUMCODES-1)-1:0]   wraddr;
input  [           CODEBITS -1:0]   wrdata;
input                               run;
output                              done;
input  [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
output [            OUTWIDTH-1:0]   rddata;

wire                              rstn;
wire                              clk;
wire                              wren;
wire [  clogb2(NUMCODES-1)-1:0]   wraddr;
wire [           CODEBITS -1:0]   wrdata;
wire                              run;
wire                              done;
wire [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
reg  [            OUTWIDTH-1:0]   rddata;

reg  [clogb2(NUMCODES)-1:0] blcount  [BITLENGTH];
reg  [   (1<<CODEBITS)-1:0] nextcode [BITLENGTH+1];

initial for(int i=0; i< BITLENGTH; i++)  blcount[i] = '0;
initial for(int i=0; i<=BITLENGTH; i++) nextcode[i] = '0;

reg  clear_tree2d = 1'b0;
reg  build_tree2d = 1'b0;
reg  [clogb2(BITLENGTH)-1:0] idx = '0;
reg  [clogb2(2*NUMCODES-1)-1:0] clearidx = '0;
reg  [ clogb2(NUMCODES)-1:0] nn='0, nnn, lnn='0;
reg  [CODEBITS-1:0] ii='0, lii='0;
reg  [CODEBITS-1:0] blenn, blen = '0;
wire [(1<<CODEBITS)-1:0] tree1d = nextcode[blen];
wire                     islast = (blen==0 || ii==0);
reg  [clogb2(2*NUMCODES-1)-1:0] nodefilled = '0;
reg  [clogb2(2*NUMCODES-1)-1:0] ntreepos, treepos='0;
wire [clogb2(2*NUMCODES-1)-1:0] ntpos= {ntreepos[clogb2(2*NUMCODES-1)-2:0], tree1d[ii]};
reg  [clogb2(2*NUMCODES-1)-1:0] tpos = '0;
reg         rdfilled;
reg         valid = 1'b0;
wire [OUTWIDTH-1:0] wrtree2d = (lii==0) ? lnn : nodefilled + (clogb2(2*NUMCODES-1))'(NUMCODES);
reg  alldone = 1'b0;

assign done = alldone & run;

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        valid <= '0;
        treepos <= '0;
        tpos <= '0;
        lii <= '0;
        lnn <= '0;
    end else begin
        valid <= build_tree2d & nn<NUMCODES & blen>0;
        treepos <= ntreepos;
        tpos <= ntpos;
        lii <= ii;
        lnn <= nn;
    end

always @ (posedge clk or negedge rstn)
    if(~rstn)
        blen <= '0;
    else begin
        if(islast) blen <= blenn;
    end

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        for(int i=0; i<BITLENGTH; i++)
            blcount[i] <= '0;
    end else begin
        if(done) begin
            for(int i=0; i<BITLENGTH; i++)
                blcount[i] <= '0;
        end else begin
            if(wren && wrdata<BITLENGTH)
                blcount[wrdata] <= blcount[wrdata] + (clogb2(NUMCODES))'(1);
        end
    end

always_comb
    if(build_tree2d)
        nnn = (nn<NUMCODES && islast) ? nn + (clogb2(NUMCODES))'(1) : nn;
    else
        nnn = (idx<BITLENGTH) ? '1 : '0;
        
always @ (posedge clk or negedge rstn)
    if(~rstn)
        nn <= '0;
    else
        nn <= nnn;

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        for(int i=0; i<=BITLENGTH; i++) nextcode[i] <= '0;
        alldone <= 1'b0;
        ii <= '0;
        idx <= '0;
        build_tree2d <= 1'b0;
        clearidx <= '0;
        clear_tree2d <= 1'b0;
    end else begin
        nextcode[0] <= '0;
        alldone <= 1'b0;
        if(run) begin
            if(~clear_tree2d) begin
                if( clearidx >= (clogb2(2*NUMCODES-1))'(2*NUMCODES-1) )
                    clear_tree2d <= 1'b1;
                clearidx <= clearidx + (clogb2(2*NUMCODES-1))'(1);
            end else if(build_tree2d) begin
                if(nn < NUMCODES) begin
                    if(islast) begin
                        ii <= blenn - (CODEBITS)'(1);
                        if(blen>0)
                            nextcode[blen] <= tree1d + (1<<CODEBITS)'(1);
                    end else
                        ii <= ii - (CODEBITS)'(1);
                end else
                    alldone <= 1'b1;
            end else begin
                if(idx<BITLENGTH) begin
                    idx <= idx + (clogb2(BITLENGTH))'(1);
                    nextcode[idx+1] <= ( ( nextcode[idx] + ((1<<CODEBITS)'(blcount[idx])) ) << 1 );
                end else begin
                    ii <= blen - (CODEBITS)'(1);
                    build_tree2d <= 1'b1;
                end
            end
        end else begin
            ii <= '0;
            idx <= '0;
            build_tree2d <= 1'b0;
            clearidx <= '0;
            clear_tree2d <= 1'b0;
        end
    end

always_comb
    if(~run)
        ntreepos = 0;
    else if(valid) begin
        if(~rdfilled)
            ntreepos = (clogb2(2*NUMCODES-1))'(rddata) - (clogb2(2*NUMCODES-1))'(NUMCODES);
        else
            ntreepos = (lii==0) ? '0 : nodefilled;
    end else
        ntreepos = treepos;
    
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        nodefilled <= '0;
    end else begin
        if(~run)
            nodefilled <=              (clogb2(2*NUMCODES-1))'(1);
        else if(valid & rdfilled & lii>0)
            nodefilled <= nodefilled + (clogb2(2*NUMCODES-1))'(1);
    end



reg [CODEBITS-1:0] mem_huffman_bitlens [NUMCODES];

always @ (posedge clk)
    if(wren)
        mem_huffman_bitlens[wraddr] <= wrdata;

wire [clogb2(NUMCODES-1)-1:0] mem_rdaddr = (clogb2(NUMCODES-1))'(nnn) + (clogb2(NUMCODES-1))'(1);

always @ (posedge clk)
    blenn <= mem_huffman_bitlens[mem_rdaddr];



reg [OUTWIDTH:0] mem_tree2d [2*NUMCODES];

always @ (posedge clk)
    if( ~clear_tree2d | (valid & rdfilled) )
        mem_tree2d[ (clogb2(2*NUMCODES-1))'(~clear_tree2d ? clearidx : tpos ) ] <= ~clear_tree2d ? {1'b1, (OUTWIDTH)'(0)} : {1'b0, wrtree2d};

always @ (posedge clk)
    {rdfilled, rddata} <= mem_tree2d[ (clogb2(2*NUMCODES-1))'(alldone ? rdaddr : ntpos ) ];

endmodule
