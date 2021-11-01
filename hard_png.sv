`timescale 1 ns/1 ns



module hard_png(
    input  wire         rst,
    input  wire         clk,
    // png data input stream
    input  wire         ivalid,
    output wire         iready,
    input  wire [ 7:0]  ibyte,
    // image frame configuration output
    output wire         newframe,
    output wire [ 1:0]  colortype, // 0:gray   1:gray+A   2:RGB   3:RGBA
    output wire [13:0]  width,     // horizontal size / frame width  / pixel per row
    output wire [31:0]  height,    //   vertical size / frame height / rows per frame 
    // pixel output
    output wire         ovalid,
    output wire [ 7:0]  opixelr, opixelg, opixelb, opixela
);

wire         reset;
wire [13:0]  bpr;   // bytes per row
wire [ 1:0]  bpp;   // bytes per pixel

wire         pvalid;
wire         pready;
wire [ 7:0]  pbyte;

wire         mvalid;
wire [ 7:0]  mbyte;

wire         bvalid;
wire [ 7:0]  bbyte;

wire         isplte;
wire         plte_wen;
wire [ 7:0]  plte_waddr;
wire [23:0]  plte_wdata;
wire [ 7:0]  plte_raddr;
wire [23:0]  plte_rdata;

assign colortype = isplte ? 2'd2 : bpp;

png_parser png_parser_i(
    .rst        ( rst         ),
    .orst       ( reset       ),
    .clk        ( clk         ),
    .oframe     ( newframe    ),
    .isplte     ( isplte      ),
    .bpp        ( bpp         ),
    .ppr        ( width       ),
    .bpr        ( bpr         ),
    .rpf        ( height      ),
    .ivalid     ( ivalid      ),
    .iready     ( iready      ),
    .ibyte      ( ibyte       ),
    .ovalid     ( pvalid      ),
    .oready     ( pready      ),
    .obyte      ( pbyte       ),
    .plte_wen   ( plte_wen    ),
    .plte_waddr ( plte_waddr  ),
    .plte_wdata ( plte_wdata  )
);

uz_inflate uz_inflate_i(
    .rst        ( reset       ),
    .clk        ( clk         ),
    .ivalid     ( pvalid      ),
    .iready     ( pready      ),
    .ibyte      ( pbyte       ),
    .ovalid     ( mvalid      ),
    .obyte      ( mbyte       ),
    .end_stream (             )
);

unfilter unfilter_i(
    .rst        ( reset       ),
    .clk        ( clk         ),
    .bpp        ( bpp         ),
    .bpr        ( bpr         ),
    .ivalid     ( mvalid      ),
    .idata      ( mbyte       ),
    .ovalid     ( bvalid      ),
    .odata      ( bbyte       )
);

build_pixel build_pixel_i(
    .clk        ( clk         ),
    .newframe   ( newframe    ),
    .bpp        ( bpp         ),
    .isplte     ( isplte      ),
    .plte_raddr ( plte_raddr  ),
    .plte_rdata ( plte_rdata  ),
    .ivalid     ( bvalid      ),
    .ibyte      ( bbyte       ),
    .ovalid     ( ovalid      ),
    .opixelr    ( opixelr     ),
    .opixelg    ( opixelg     ),
    .opixelb    ( opixelb     ),
    .opixela    ( opixela     )
);

RamSinglePort #(
    .SIZE       ( 256              ),
    .WIDTH      ( 24               )
) ram_for_plte (
    .clk        ( clk              ),
    .wen        ( plte_wen         ),
    .waddr      ( 8'(plte_waddr)   ),
    .wdata      ( plte_wdata       ),
    .raddr      ( 8'(plte_raddr)   ),
    .rdata      ( plte_rdata       )
);

endmodule





























module build_pixel(
    input  wire        clk,
    input  wire        newframe,
    input  wire [ 1:0] bpp,
    input  wire        isplte,
    output wire [ 7:0] plte_raddr,
    input  wire [23:0] plte_rdata,
    input  wire        ivalid,
    input  wire [ 7:0] ibyte,
    output reg         ovalid,
    output wire [ 7:0] opixelr, opixelg, opixelb, opixela
);
initial ovalid = 1'b0;
reg [1:0] pixcnt = '0;
reg [7:0] pr='0, pg='0, pb='0, pa='0;

assign plte_raddr = ibyte;

assign opixelr = ovalid ? (isplte ? plte_rdata[23:16] : pr) : 8'h0;
assign opixelg = ovalid ? (isplte ? plte_rdata[15: 8] : pg) : 8'h0;
assign opixelb = ovalid ? (isplte ? plte_rdata[ 7: 0] : pb) : 8'h0;
assign opixela = ovalid ? (isplte ?             8'hff : pa) : 8'h0;

always @ (posedge clk)
    if(newframe) begin
        pixcnt <= '0;
        ovalid <= 1'b0;
        {pr, pg, pb, pa} <= 0;
    end else if(ivalid) begin
        case(pixcnt)
        2'd0 : {pr, pg, pb, pa} <= {ibyte, ibyte, ibyte, 8'hff};
        2'd1 : {            pa} <= {                     ibyte};
        2'd2 : {    pg, pb, pa} <= {          pa, ibyte, 8'hff};
        2'd3 : {            pa} <= {                     ibyte};
        endcase
        if(pixcnt<bpp) begin
            pixcnt <= pixcnt + 2'd1;
            ovalid <= 1'b0;
        end else begin
            pixcnt <= 2'd0;
            ovalid <= 1'b1;
        end
    end else
        ovalid <= 1'b0;

endmodule





























module png_parser(
    input  wire         rst,
    input  wire         clk,
    // data input
    input  wire         ivalid,
    output reg          iready,
    input  wire [ 7:0]  ibyte,
    // data output
    output reg          ovalid,
    input  wire         oready,
    output reg  [ 7:0]  obyte,
    // image parameters out
    output wire         orst,
    output reg          oframe,
    output reg          isplte,
    output reg  [ 1:0]  bpp,   // bytes per pixel
    output reg  [13:0]  ppr,   // pixel per row
    output reg  [13:0]  bpr,   // bytes per row
    output reg  [31:0]  rpf,   // rows per frame
    // PLTE RAM write port
    output reg          plte_wen,
    output reg  [ 7:0]  plte_waddr,
    output reg  [23:0]  plte_wdata
);

initial oframe = 1'b0;
initial isplte = 1'b0;
initial bpp = '0;
initial ppr = '0;
initial bpr = '0;
initial rpf = '0;
initial plte_wen = 1'b0;
initial plte_waddr = '0;
initial plte_wdata = '0;

wire     ispltes [8]; assign ispltes[0]=1'b0; assign ispltes[1]=1'b0; assign ispltes[2]=1'b0; assign ispltes[3]=1'b1; assign ispltes[4]=1'b0; assign ispltes[5]=1'b0; assign ispltes[6]=1'b0; assign ispltes[7]=1'b0;
wire [ 1:0] bpps [8]; assign bpps[0]=2'd0; assign bpps[1]=2'd0; assign bpps[2]=2'd2; assign bpps[3]=2'd0; assign bpps[4]=2'd1; assign bpps[5]=2'd0; assign bpps[6]=2'd3; assign bpps[7]=2'd0;

wire [63:0] png_precode = 64'h89504e470d0a1a0a;
wire [31:0] ihdr_name = 32'h49484452;
wire [31:0] plte_name = 32'h504C5445;
wire [31:0] idat_name = 32'h49444154;
wire [31:0] iend_name = 32'h49454e44;

reg  [ 7:0] latchbytes [7];
wire [ 7:0] lastbytes [8];
wire [63:0] lastlbytes;
wire [31:0] h32bit = lastlbytes[63:32];
wire [31:0] l32bit = lastlbytes[31: 0];

assign lastbytes[7] = ibyte;

initial {latchbytes[0],latchbytes[1],latchbytes[2],latchbytes[3],latchbytes[4],latchbytes[5],latchbytes[6]} = '0;

generate genvar ii;
    for(ii=0; ii<7; ii++) begin : generate_latchbytes_connect
        assign lastbytes[ii] = latchbytes[ii];
        always @ (posedge clk or posedge rst)
            if(rst)
                latchbytes[ii] <= '0;
            else begin
                if(ivalid)
                    latchbytes[ii] <= lastbytes[ii+1];
            end
    end
endgenerate

assign lastlbytes[ 7: 0] = lastbytes[7];
assign lastlbytes[15: 8] = lastbytes[6];
assign lastlbytes[23:16] = lastbytes[5];
assign lastlbytes[31:24] = lastbytes[4];
assign lastlbytes[39:32] = lastbytes[3];
assign lastlbytes[47:40] = lastbytes[2];
assign lastlbytes[55:48] = lastbytes[1];
assign lastlbytes[63:56] = lastbytes[0];

reg  [ 2:0] bcnt= '0;
reg  [31:0] cnt = '0;
reg  [ 2:0] crccnt = '0;
reg  [ 2:0] gapcnt = '0;

enum {NONE, IHDR, PLTE, IDAT, IEND} curr_name = NONE;
reg busy = 1'b0;
reg sizevalid = 1'b0;
reg imagevalid = 1'b0;

reg          ispltetmp = 1'b0;
reg  [ 1:0]  bpptmp = '0;   // bytes per pixel
reg  [13:0]  pprtmp = '0;   // pixel per row
reg  [15:0]  bprtmp = '0;   // bytes per row
reg  [31:0]  rpftmp = '0;   // rows per frame

reg  [ 1:0]  plte_bytecnt = '0;
reg  [ 7:0]  plte_pixcnt  = '0;

assign orst = ~imagevalid;

wire parametervalid =   (   lastbytes[7]==8'h0 &&
                            lastbytes[6]==8'h0 &&
                            lastbytes[5]==8'h0 &&
                            lastbytes[3]==8'h8 &&
                            (   lastbytes[4]==8'h0 ||
                                lastbytes[4]==8'h2 ||
                                lastbytes[4]==8'h3 ||
                                lastbytes[4]==8'h4 ||
                                lastbytes[4]==8'h6
                            )
                        );

always_comb
    if(ivalid && imagevalid && cnt>0 && curr_name==IDAT && gapcnt==2'd0) begin
        ovalid <= 1'b1;
        iready <= oready;
        obyte  <= ibyte;
    end else begin
        ovalid <= 1'b0;
        iready <= 1'b1;
        obyte  <= '0;
    end

always @ (posedge clk or posedge rst)
    if(rst) begin
        bcnt <= '0;
        cnt  <= '0;
        crccnt <= '0;
        gapcnt <= '0;
        busy <= 1'b0;
        sizevalid <= 1'b0;
        imagevalid <= 1'b0;
        curr_name <= NONE;
        ispltetmp <= 1'b0;
        bpptmp <= '0;
        pprtmp <= '0;
        bprtmp <= '0;
        rpftmp <= '0;
        isplte <= 1'b0;
        bpp    <= '0;
        ppr    <= '0;
        bpr    <= '0;
        rpf    <= '0;
        oframe <= 1'b0;
        plte_wen <= 1'b0;
        plte_waddr <= '0;
        plte_wdata <= '0;
        plte_bytecnt <= '0;
        plte_pixcnt  <= '0;
    end else begin
        oframe <= 1'b0;
        plte_wen <= 1'b0;
        plte_waddr <= '0;
        plte_wdata <= '0;
        if(ivalid) begin
            plte_bytecnt <= '0;
            plte_pixcnt  <= '0;
            if(~busy) begin
                bcnt <= '0;
                cnt  <= '0;
                crccnt <= '0;
                busy <= (lastlbytes==png_precode);
            end else begin
                if(cnt>0) begin
                    bcnt <= '0;
                    if(curr_name==IHDR) begin
                        cnt  <= cnt - 1;
                        gapcnt <= 2'd2;
                        if(cnt==6) begin
                            imagevalid <= 1'b0;
                            rpftmp <= l32bit;
                            if(h32bit[31:14]=='0) begin
                                sizevalid <= 1'b1;
                                pprtmp <= h32bit[13:0];
                            end else begin
                                sizevalid <= 1'b0;
                                pprtmp <= '1;
                            end
                        end else if(cnt==3) begin
                            ispltetmp <= ispltes[lastlbytes[10:8]];
                            bpptmp <= bpps[lastlbytes[10:8]];
                        end else if(cnt==2) begin
                            case(bpptmp)
                            2'd0 : bprtmp <= {2'b00, pprtmp};
                            2'd1 : bprtmp <= {1'b0, pprtmp, 1'b0};
                            2'd2 : bprtmp <= {1'b0, pprtmp, 1'b0} + {2'b00, pprtmp};
                            2'd3 : bprtmp <= {pprtmp, 2'b00};
                            endcase
                        end else if(cnt==1) begin
                            if(sizevalid && parametervalid && (bprtmp[15:14]==2'd0)) begin
                                oframe <= 1'b1;
                                imagevalid <= 1'b1;
                                isplte <= ispltetmp;
                                bpp <= bpptmp;
                                ppr <= pprtmp;
                                bpr <= bprtmp[13:0];
                                rpf <= rpftmp;
                            end else begin
                                imagevalid <= 1'b0;
                                isplte <= 1'b0;
                                bpp <= '0;
                                ppr <= '0;
                                bpr <= '0;
                                rpf <= '0;
                            end
                        end
                    end else if(curr_name==IDAT) begin
                        if(gapcnt>2'd0)
                            gapcnt <= gapcnt - 2'd1;
                        if(imagevalid && gapcnt==2'd0) begin
                            if(oready)
                                cnt <= cnt - 1;
                        end else begin
                            cnt <= cnt - 1;
                        end
                    end else if(curr_name==PLTE) begin
                        plte_pixcnt <= plte_pixcnt;
                        case(plte_bytecnt)
                        2'd0   :plte_bytecnt <= 2'd1;
                        2'd1   :plte_bytecnt <= 2'd2;
                        default:begin 
                                plte_bytecnt <= 2'd0;
                                plte_pixcnt  <= plte_pixcnt + 8'd1;
                                plte_wen     <= 1'b1;
                                plte_waddr   <= plte_pixcnt;
                                plte_wdata   <= lastlbytes[23:0];
                            end
                        endcase
                        cnt <= cnt - 1;
                    end else begin
                        cnt <= cnt - 1;
                    end
                end else if(crccnt>3'd0) begin
                    bcnt <= '0;
                    cnt  <= '0;
                    crccnt <= crccnt - 3'd1;
                    if(crccnt==3'd1) begin
                        if(curr_name==IEND) begin
                            busy <= 1'b0;
                        end
                        curr_name <= NONE;
                    end
                end else begin
                    if(bcnt==3'd7) begin
                        cnt <= h32bit;
                        crccnt <= 3'd4;
                        if     (l32bit==ihdr_name)
                            curr_name <= IHDR;
                        else if(l32bit==plte_name)
                            curr_name <= PLTE;
                        else if(l32bit==idat_name)
                            curr_name <= IDAT;
                        else if(l32bit==iend_name)
                            curr_name <= IEND;
                        else
                            curr_name <= NONE;
                    end
                    bcnt <= bcnt + 3'd1;
                end
            end
        end
    end

endmodule

















module uz_inflate(
    input  wire        rst,
    input  wire        clk,
    input  wire        ivalid,
    output reg         iready,
    input  wire  [7:0] ibyte,
    output reg         ovalid,
    output reg   [7:0] obyte,
    output wire        end_stream
);

initial ovalid = 1'b0;
initial obyte  = '0;

wire       huffman_ovalid;
wire [7:0] huffman_obyte;
reg        raw_ovalid;
reg  [7:0] raw_obyte;

reg        raw_mode = 1'b0;
wire       raw_format;

reg [ 2:0] status = '0;
reg [15:0] rcnt = '0;
reg [ 2:0] cnt = '0;
reg [ 7:0] rbyte = '0;

reg       tvalid;
wire      tready;
reg       tbit;

always @ (posedge clk or posedge rst)
    if(rst) begin
        ovalid <= 1'b0;
        obyte  <= '0;
    end else begin
        if(raw_mode) begin
            ovalid <= raw_ovalid;
            obyte  <= raw_obyte;
        end else begin
            ovalid <= huffman_ovalid;
            obyte  <= huffman_obyte;
        end
    end

always_comb
    if(rst) begin
        raw_ovalid <= 1'b0;
        raw_obyte  <= '0;
        iready <= 1'b0;
        tvalid <= 1'b0;
        tbit   <= 1'b0;
    end else begin
        raw_ovalid <= 1'b0;
        raw_obyte  <= '0;
        if(raw_mode) begin
            iready <= 1'b1;
            tvalid <= 1'b0;
            tbit   <= 1'b0;
            if(status>=3) begin
                raw_ovalid <= ivalid;
                raw_obyte  <= ibyte;
            end
        end else begin
            if(raw_format) begin
                iready <= 1'b1;
                tvalid <= 1'b0;
                tbit   <= 1'b0;
            end else if(cnt==3'h0) begin
                iready <= tready;
                tvalid <= ivalid;
                tbit   <= ibyte[0];
            end else begin
                iready <= 1'b0;
                tvalid <= 1'b1;
                tbit   <= rbyte[cnt];
            end
        end
    end

always @ (posedge clk or posedge rst)
    if(rst) begin
        raw_mode <= 1'b0;
        cnt <= '0;
        rbyte <= '0;
        rcnt <= '0;
        status <= '0;
    end else begin
        if(raw_mode) begin
            cnt <= '0;
            rbyte <= '0;
            if(ivalid) begin
                if         (status==0) begin
                    rcnt[15:8] <= ibyte;
                    status <= status + 3'h1;
                end else if(status==1) begin
                    status <= status + 3'h1;
                end else if(status==2) begin
                    if(rcnt>0) begin
                        rcnt <= rcnt - 16'd1;
                        status <= status + 3'h1;
                    end else begin
                        raw_mode <= 1'b0;
                        status <= '0;
                    end
                end else begin
                    if(rcnt>0) begin
                        rcnt <= rcnt - 16'd1;
                    end else begin
                        raw_mode <= 1'b0;
                        status <= '0;
                    end
                end
            end
        end else begin
            rcnt <= '0;
            status <= '0;
            if(raw_format) begin
                if(ivalid) begin
                    raw_mode <= 1'b1;
                    rcnt[ 7:0] <= ibyte;
                end
                cnt <= '0;
                rbyte <= '0;
            end else begin
                if(cnt==3'h0) begin
                    if(ivalid & tready) begin
                        cnt <= cnt + 3'h1;
                        rbyte <= ibyte;
                    end
                end else begin
                    if(tready)
                        cnt <= cnt + 3'h1;
                end
            end
        end
    end


huffman_inflate huffman_inflate_i(
    .rst        ( raw_mode | rst ),
    .clk        ( clk            ),
    .ivalid     ( tvalid         ),
    .iready     ( tready         ),
    .ibit       ( tbit           ),
    .ovalid     ( huffman_ovalid ),
    .obyte      ( huffman_obyte  ),
    .raw_format ( raw_format     ),
    .end_stream ( end_stream     )
);

endmodule











module huffman_inflate(
    input  wire        rst,
    input  wire        clk,
    input  wire        ivalid,
    output wire        iready,
    input  wire        ibit,
    output wire        ovalid,
    output wire  [7:0] obyte,
    output reg         raw_format,
    output reg         end_stream
);

initial  {raw_format, end_stream} = '0;

wire [ 4:0] CLCL [19]; assign CLCL[0]=5'd16; assign CLCL[1]=5'd17; assign CLCL[2]=5'd18; assign CLCL[3]=5'd0; assign CLCL[4]=5'd8; assign CLCL[5]=5'd7; assign CLCL[6]=5'd9; assign CLCL[7]=5'd6; assign CLCL[8]=5'd10; assign CLCL[9]=5'd5; assign CLCL[10]=5'd11; assign CLCL[11]=5'd4; assign CLCL[12]=5'd12; assign CLCL[13]=5'd3; assign CLCL[14]=5'd13; assign CLCL[15]=5'd2; assign CLCL[16]=5'd14; assign CLCL[17]=5'd1; assign CLCL[18]=5'd15;
wire [ 8:0] LENGTH_BASE [30]; assign LENGTH_BASE[0]=9'd0; assign LENGTH_BASE[1]=9'd3; assign LENGTH_BASE[2]=9'd4; assign LENGTH_BASE[3]=9'd5; assign LENGTH_BASE[4]=9'd6; assign LENGTH_BASE[5]=9'd7; assign LENGTH_BASE[6]=9'd8; assign LENGTH_BASE[7]=9'd9; assign LENGTH_BASE[8]=9'd10; assign LENGTH_BASE[9]=9'd11; assign LENGTH_BASE[10]=9'd13; assign LENGTH_BASE[11]=9'd15; assign LENGTH_BASE[12]=9'd17; assign LENGTH_BASE[13]=9'd19; assign LENGTH_BASE[14]=9'd23; assign LENGTH_BASE[15]=9'd27; assign LENGTH_BASE[16]=9'd31; assign LENGTH_BASE[17]=9'd35; assign LENGTH_BASE[18]=9'd43; assign LENGTH_BASE[19]=9'd51; assign LENGTH_BASE[20]=9'd59; assign LENGTH_BASE[21]=9'd67; assign LENGTH_BASE[22]=9'd83; assign LENGTH_BASE[23]=9'd99; assign LENGTH_BASE[24]=9'd115; assign LENGTH_BASE[25]=9'd131; assign LENGTH_BASE[26]=9'd163; assign LENGTH_BASE[27]=9'd195; assign LENGTH_BASE[28]=9'd227; assign LENGTH_BASE[29]=9'd258;
wire [ 2:0] LENGTH_EXTRA [30]; assign LENGTH_EXTRA[0]=3'd0; assign LENGTH_EXTRA[1]=3'd0; assign LENGTH_EXTRA[2]=3'd0; assign LENGTH_EXTRA[3]=3'd0; assign LENGTH_EXTRA[4]=3'd0; assign LENGTH_EXTRA[5]=3'd0; assign LENGTH_EXTRA[6]=3'd0; assign LENGTH_EXTRA[7]=3'd0; assign LENGTH_EXTRA[8]=3'd0; assign LENGTH_EXTRA[9]=3'd1; assign LENGTH_EXTRA[10]=3'd1; assign LENGTH_EXTRA[11]=3'd1; assign LENGTH_EXTRA[12]=3'd1; assign LENGTH_EXTRA[13]=3'd2; assign LENGTH_EXTRA[14]=3'd2; assign LENGTH_EXTRA[15]=3'd2; assign LENGTH_EXTRA[16]=3'd2; assign LENGTH_EXTRA[17]=3'd3; assign LENGTH_EXTRA[18]=3'd3; assign LENGTH_EXTRA[19]=3'd3; assign LENGTH_EXTRA[20]=3'd3; assign LENGTH_EXTRA[21]=3'd4; assign LENGTH_EXTRA[22]=3'd4; assign LENGTH_EXTRA[23]=3'd4; assign LENGTH_EXTRA[24]=3'd4; assign LENGTH_EXTRA[25]=3'd5; assign LENGTH_EXTRA[26]=3'd5; assign LENGTH_EXTRA[27]=3'd5; assign LENGTH_EXTRA[28]=3'd5; assign LENGTH_EXTRA[29]=3'd0;
wire [14:0] DISTANCE_BASE [30]; assign DISTANCE_BASE[0]=15'd1; assign DISTANCE_BASE[1]=15'd2; assign DISTANCE_BASE[2]=15'd3; assign DISTANCE_BASE[3]=15'd4; assign DISTANCE_BASE[4]=15'd5; assign DISTANCE_BASE[5]=15'd7; assign DISTANCE_BASE[6]=15'd9; assign DISTANCE_BASE[7]=15'd13; assign DISTANCE_BASE[8]=15'd17; assign DISTANCE_BASE[9]=15'd25; assign DISTANCE_BASE[10]=15'd33; assign DISTANCE_BASE[11]=15'd49; assign DISTANCE_BASE[12]=15'd65; assign DISTANCE_BASE[13]=15'd97; assign DISTANCE_BASE[14]=15'd129; assign DISTANCE_BASE[15]=15'd193; assign DISTANCE_BASE[16]=15'd257; assign DISTANCE_BASE[17]=15'd385; assign DISTANCE_BASE[18]=15'd513; assign DISTANCE_BASE[19]=15'd769; assign DISTANCE_BASE[20]=15'd1025; assign DISTANCE_BASE[21]=15'd1537; assign DISTANCE_BASE[22]=15'd2049; assign DISTANCE_BASE[23]=15'd3073; assign DISTANCE_BASE[24]=15'd4097; assign DISTANCE_BASE[25]=15'd6145; assign DISTANCE_BASE[26]=15'd8193; assign DISTANCE_BASE[27]=15'd12289; assign DISTANCE_BASE[28]=15'd16385; assign DISTANCE_BASE[29]=15'd24577;
wire [ 3:0] DISTANCE_EXTRA [30]; assign DISTANCE_EXTRA[0]=4'd0; assign DISTANCE_EXTRA[1]=4'd0; assign DISTANCE_EXTRA[2]=4'd0; assign DISTANCE_EXTRA[3]=4'd0; assign DISTANCE_EXTRA[4]=4'd1; assign DISTANCE_EXTRA[5]=4'd1; assign DISTANCE_EXTRA[6]=4'd2; assign DISTANCE_EXTRA[7]=4'd2; assign DISTANCE_EXTRA[8]=4'd3; assign DISTANCE_EXTRA[9]=4'd3; assign DISTANCE_EXTRA[10]=4'd4; assign DISTANCE_EXTRA[11]=4'd4; assign DISTANCE_EXTRA[12]=4'd5; assign DISTANCE_EXTRA[13]=4'd5; assign DISTANCE_EXTRA[14]=4'd6; assign DISTANCE_EXTRA[15]=4'd6; assign DISTANCE_EXTRA[16]=4'd7; assign DISTANCE_EXTRA[17]=4'd7; assign DISTANCE_EXTRA[18]=4'd8; assign DISTANCE_EXTRA[19]=4'd8; assign DISTANCE_EXTRA[20]=4'd9; assign DISTANCE_EXTRA[21]=4'd9; assign DISTANCE_EXTRA[22]=4'd10; assign DISTANCE_EXTRA[23]=4'd10; assign DISTANCE_EXTRA[24]=4'd11; assign DISTANCE_EXTRA[25]=4'd11; assign DISTANCE_EXTRA[26]=4'd12; assign DISTANCE_EXTRA[27]=4'd12; assign DISTANCE_EXTRA[28]=4'd13; assign DISTANCE_EXTRA[29]=4'd13;

reg        irepeat = 1'b0;
reg        srepeat = 1'b0;

reg symbol_valid = 1'b0;
reg [7:0] symbol  = '0;

reg  decoder_nreset = 1'b0;

reg  [ 1:0] iword = '0;
reg  [ 1:0] ibcnt = '0;
reg  [ 4:0] precode_wpt = '0;

reg         bfin  = 1'b0;
reg         bfix  = 1'b0;
reg         fixed_tree = 1'b0;
reg  [13:0] precode_reg  = '0;
wire [ 4:0] hclen = 5'd4   + {1'b0, precode_reg[13:10]};
wire [ 8:0] hlit  = 9'd257 +        precode_reg[ 4: 0]; 
wire [ 8:0] hdist = 9'd1   + {4'h0, precode_reg[ 9: 5]};
wire [ 8:0] hmax  = hlit + hdist;
wire [ 8:0] hend  = (hlit+9'd32>9'd288) ? hlit+9'd32 : 9'd288;

reg  [ 4:0] lentree_wpt  = '0;
reg  [ 8:0] tree_wpt = '0;

wire        lentree_codeen;   
wire [ 5:0] lentree_code;
wire        codetree_codeen;
wire [ 9:0] codetree_code;
wire        distree_codeen;
wire [ 9:0] distree_code;

reg  [ 2:0] repeat_code_pt  = '0;
enum {REPEAT_NONE, REPEAT_PREVIOUS, REPEAT_ZERO_FEW, REPEAT_ZERO_MANY} repeat_mode = REPEAT_NONE;
reg  [ 6:0] repeat_code='0;
reg  [ 7:0] repeat_len ='0;
reg  [ 5:0] repeat_val = '0;

reg         lentree_run = 1'b0;
wire        lentree_done;
reg         tree_run = 1'b0;
wire        codetree_done;
wire        distree_done;
wire        tree_done = (codetree_done & distree_done) | fixed_tree;

reg  [ 2:0] tcnt =3'h0, tmax =3'h0;
reg  [ 3:0] dscnt=4'h0, dsmax=4'h0;

enum {T, D, R, S} status = T;

wire   lentree_ien  = ~end_stream & ~raw_format & ivalid & lentree_done &  ~lentree_codeen & (repeat_mode==REPEAT_NONE && repeat_len==8'd0) & (tree_wpt<hmax);
wire   codetree_ien = ~end_stream & ~raw_format & ivalid & tree_done    & ~codetree_codeen & (tcnt==3'd0) & (dscnt==4'd0) & (status==T);
wire   distree_ien  = ~end_stream & ~raw_format & ivalid & tree_done    &  ~distree_codeen & (tcnt==3'd0) & (dscnt==4'd0) & (status==D);

assign iready = end_stream | (~raw_format & (
    ( precode_wpt<17 || lentree_wpt<hclen ) |
    ( lentree_done & ~lentree_codeen & ((repeat_mode==REPEAT_NONE && repeat_len==8'd0) | repeat_code_pt>3'd0) & (tree_wpt<hmax) ) |
    ( tree_done & ~codetree_codeen & ~distree_codeen & (status==T || status==D || (status==R && dscnt>4'd0)) ) ) );

reg  [ 8:0] lengthb= '0;
reg  [ 5:0] lengthe= '0;
wire [ 8:0] length = lengthb + lengthe;
reg  [ 8:0] len_last = '0;

reg  [15:0] distanceb='0;
reg  [15:0] distancee='0;
wire [15:0] distance = distanceb + distancee;

reg         lentree_wen = 1'b0;
reg  [ 4:0] lentree_waddr = '0;
reg  [ 2:0] lentree_wdata = '0;
reg         codetree_wen = 1'b0;
reg  [ 8:0] codetree_waddr = '0;
reg  [ 5:0] codetree_wdata = '0;
reg         distree_wen = 1'b0;
reg  [ 4:0] distree_waddr = '0;
reg  [ 5:0] distree_wdata = '0;

wire [ 5:0] lentree_raddr;
wire [ 5:0] lentree_rdata;
wire [ 9:0] codetree_raddr;
wire [ 9:0] codetree_rdata, codetree_rdata_fixed;
wire [ 5:0] distree_raddr;
wire [ 9:0] distree_rdata, distree_rdata_fixed;

task automatic lentree_write(input wen=1'b0, input [4:0] waddr='0, input [2:0] wdata='0);
    lentree_wen   <= wen;
    lentree_waddr <= waddr;
    lentree_wdata <= wdata;
endtask

task automatic codetree_write(input wen=1'b0, input [8:0] waddr='0, input [5:0] wdata='0);
    codetree_wen   <= wen;
    codetree_waddr <= waddr;
    codetree_wdata <= wdata;
endtask

task automatic distree_write(input wen=1'b0, input [4:0] waddr='0, input [5:0] wdata='0);
    distree_wen   <= wen;
    distree_waddr <= waddr;
    distree_wdata <= wdata;
endtask

task automatic reset_all_regs();
    decoder_nreset <= 1'b0;
    {bfin, bfix, fixed_tree} <= '0;
    iword <= '0;
    ibcnt <= '0;
    precode_wpt <= '0;
    precode_reg <= '0;
    lentree_wpt <= '0;
    lentree_run <= 1'b0;
    tree_run    <= 1'b0;
    lentree_write();
    codetree_write();
    distree_write();
    repeat_code_pt <= '0;
    repeat_mode <= REPEAT_NONE;
    repeat_code <= '0;
    repeat_len <= '0;
    repeat_val <= '0;
    tree_wpt   <= '0;
    tcnt     <= '0;
    tmax     <= '0;
    lengthb  <= '0;
    lengthe  <= '0;
    distanceb<= '0;
    distancee<= '0;
    dscnt    <= '0;
    dsmax    <= '0;
    status   <= T;
    symbol_valid <= 1'b0;
    symbol       <= '0;
    irepeat  <= 1'b0;
    srepeat  <= 1'b0;
    len_last <= '0;
endtask

always @ (posedge clk or posedge rst)
    if(rst) begin
        {raw_format, end_stream} <= '0;
        reset_all_regs();
    end else begin
        symbol_valid <= 1'b0;
        symbol       <= '0;
        irepeat  <= 1'b0;
        srepeat  <= 1'b0;
        decoder_nreset <= 1'b1;
        lentree_write();
        codetree_write();
        distree_write();
        if(precode_wpt<=2) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            if(ivalid) begin
                precode_wpt <= precode_wpt + 5'd1;
                if(precode_wpt==0) begin
                    bfin <= ibit;
                end else if(precode_wpt==1) begin
                    bfix <= ibit;
                end else begin
                    case({ibit,bfix})
                    2'b00 :
                        raw_format <= 1'b1;
                    2'b01 : begin
                        precode_wpt <= '1;
                        lentree_wpt <= '1;
                        tree_wpt <= '1;
                        fixed_tree <= 1'b1;
                    end
                    endcase
                end
            end
        end else if(precode_wpt<17) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            if(ivalid) begin
                precode_reg <= {ibit, precode_reg[13:1]};
                precode_wpt <= precode_wpt + 5'd1;
            end
        end else if(lentree_wpt<hclen) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            if(ivalid) begin
                if(ibcnt<2'd2) begin
                    iword[ibcnt[0]] <= ibit;
                    ibcnt <= ibcnt + 2'd1;
                end else begin
                    lentree_write(1'b1, CLCL[lentree_wpt], {ibit, iword});
                    ibcnt <= 2'd0;
                    lentree_wpt <= lentree_wpt + 5'd1;
                end
            end
        end else if(lentree_wpt<19) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            lentree_write(1'b1, CLCL[lentree_wpt], '0);
            lentree_wpt <= lentree_wpt + 5'd1;
        end else if(~ (lentree_done | fixed_tree)) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
        end else if(tree_wpt<hmax) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
            if(repeat_code_pt>3'd0) begin
                if(ivalid) begin
                    repeat_code_pt <= repeat_code_pt - 3'd1;
                    repeat_code[3'd7-repeat_code_pt] <= ibit;
                end
            end else if(repeat_mode>0) begin
                case(repeat_mode)
                REPEAT_PREVIOUS: begin
                    repeat_len <= repeat_code[6:5] + 8'd3;
                end
                REPEAT_ZERO_FEW: begin
                    repeat_len <= repeat_code[6:4] + 8'd3;
                end
                REPEAT_ZERO_MANY: begin
                    repeat_len <= repeat_code[6:0] + 8'd11;
                end
                default: begin
                    repeat_len <= 0;
                end
                endcase
                repeat_mode <= REPEAT_NONE;
            end else if(repeat_len>8'd0) begin
                repeat_len <= repeat_len - 8'd1;
                tree_wpt   <= tree_wpt + 9'd1;
                if(tree_wpt<288)
                    codetree_write(1'b1, tree_wpt, (tree_wpt<hlit) ? repeat_val : '0);
                if(tree_wpt>=hlit && tree_wpt<(hlit+9'd32))
                    distree_write(1'b1, tree_wpt - hlit, (tree_wpt<hmax) ? repeat_val : '0);
            end else if(lentree_codeen) begin
                case(lentree_code)
                16: begin       // repeat previous
                    repeat_mode <= REPEAT_PREVIOUS;
                    repeat_code_pt <= 3'd2;
                end
                17: begin       // repeat 0 for 3-10 times
                    repeat_mode <= REPEAT_ZERO_FEW;
                    repeat_val  <= 0;
                    repeat_code_pt <= 3'd3;
                end
                18: begin       // repeat 0 for 11-138 times
                    repeat_mode <= REPEAT_ZERO_MANY;
                    repeat_val  <= 0;
                    repeat_code_pt <= 3'd7;
                end
                default: begin  // normal value
                    repeat_mode <= REPEAT_NONE;
                    repeat_val  <= lentree_code;  // save previous code for repeat
                    repeat_code_pt <= 3'd0;
                    tree_wpt <= tree_wpt + 9'd1;
                    if(tree_wpt<288)
                        codetree_write(1'b1, tree_wpt, (tree_wpt<hlit) ? lentree_code : '0);
                    if(tree_wpt>=hlit && tree_wpt<(hlit+9'd32))
                        distree_write(1'b1, tree_wpt - hlit, (tree_wpt<hmax) ? lentree_code : '0);
                end
                endcase
                repeat_code <= '0;
            end
        end else if(tree_wpt<hend) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
            if(tree_wpt<288)
                codetree_write(1'b1, tree_wpt, '0);
            if(tree_wpt>=hlit && tree_wpt<(hlit+9'd32))
                distree_write(1'b1, tree_wpt - hlit, '0);
            tree_wpt <= tree_wpt + 9'd1;
        end else if(tree_wpt<hend+2) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
            tree_wpt <= tree_wpt + 9'd1;
        end else if(~tree_done) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b1;
        end else begin
            lentree_run <= ~fixed_tree;
            tree_run    <= ~fixed_tree;
            if(dscnt>4'd0) begin
                if(ivalid) begin
                    dscnt <= dscnt - 4'd1;
                    distancee[dsmax-dscnt] <= ibit;
                end
            end else if(tcnt>3'd0) begin
                if(ivalid) begin
                    tcnt <= tcnt - 3'd1;
                    lengthe[tmax-tcnt] <= ibit;
                end
            end else if(status==R) begin
                status <= S;
                len_last <= length;
                srepeat  <= 1'b1;
            end else if(status==S) begin
                if(len_last>0) begin
                    irepeat <= 1'b1;
                    len_last <= len_last - 9'd1;
                end else
                    status <= T;
            end else if(codetree_codeen) begin
                if(codetree_code<10'd256) begin             // normal symbol
                    symbol_valid <= 1'b1;
                    symbol       <= codetree_code[7:0];
                end else if(codetree_code==10'd256) begin   // end symbol
                    end_stream <= bfin;
                    reset_all_regs();
                end else begin                              // special symbol
                    lengthb<= LENGTH_BASE[codetree_code-10'd256];
                    lengthe<= '0;
                    tcnt   <= LENGTH_EXTRA[codetree_code-10'd256];
                    tmax   <= LENGTH_EXTRA[codetree_code-10'd256];
                    status <= D;
                end
            end else if(distree_codeen) begin
                distanceb<= DISTANCE_BASE[distree_code];
                distancee<= '0;
                dscnt    <= DISTANCE_EXTRA[distree_code];
                dsmax    <= DISTANCE_EXTRA[distree_code];
                status <= R;
            end
        end
    end

huffman_build #(
    .NUMCODES  ( 19             ),
    .CODEBITS  ( 3              ),
    .BITLENGTH ( 7              ),
    .OUTWIDTH  ( 6              )
) lentree_builder (
    .clk       ( clk            ),
    .wren      ( lentree_wen    ),
    .wraddr    ( lentree_waddr  ),
    .wrdata    ( lentree_wdata  ),
    .run       ( lentree_run    ),
    .done      ( lentree_done   ),
    .rdaddr    ( lentree_raddr  ),
    .rddata    ( lentree_rdata  )
);

huffman_decode_symbol #(
    .NUMCODES  ( 19             ),
    .OUTWIDTH  ( 6              )
) lentree_decoder (
    .rst       ( ~decoder_nreset),
    .clk       ( clk            ),
    .ien       ( lentree_ien    ),
    .ibit      ( ibit           ),
    .oen       ( lentree_codeen ),
    .ocode     ( lentree_code   ),
    .rdaddr    ( lentree_raddr  ),
    .rddata    ( lentree_rdata  )
);

huffman_build #(
    .NUMCODES  ( 288            ),
    .CODEBITS  ( 5              ),
    .BITLENGTH ( 15             ),
    .OUTWIDTH  ( 10             )
) codetree_builder (
    .clk       ( clk            ),
    .wren      ( codetree_wen   ),
    .wraddr    ( codetree_waddr ),
    .wrdata    ( (5)'(codetree_wdata) ),
    .run       ( tree_run       ),
    .done      ( codetree_done  ),
    .rdaddr    ( codetree_raddr ),
    .rddata    ( codetree_rdata )
);

fixed_codetree codetree_fixed(
    .clk       ( clk            ),
    .rdaddr    ( codetree_raddr ),
    .rddata    ( codetree_rdata_fixed )
);

huffman_decode_symbol #(
    .NUMCODES  ( 288            ),
    .OUTWIDTH  ( 10             )
) codetree_decoder (
    .rst       ( ~decoder_nreset),
    .clk       ( clk            ),
    .ien       ( codetree_ien   ),
    .ibit      ( ibit           ),
    .oen       ( codetree_codeen),
    .ocode     ( codetree_code  ),
    .rdaddr    ( codetree_raddr ),
    .rddata    ( fixed_tree ? codetree_rdata_fixed : codetree_rdata )
);

huffman_build #(
    .NUMCODES  ( 32             ),
    .CODEBITS  ( 5              ),
    .BITLENGTH ( 15             ),
    .OUTWIDTH  ( 10             )
) distree_builder (
    .clk       ( clk            ),
    .wren      ( distree_wen    ),
    .wraddr    ( distree_waddr  ),
    .wrdata    ( (5)'(distree_wdata)  ),
    .run       ( tree_run       ),
    .done      ( distree_done   ),
    .rdaddr    ( distree_raddr  ),
    .rddata    ( distree_rdata  )
);

fixed_distree distree_fixed(
    .clk       ( clk            ),
    .rdaddr    ( distree_raddr  ),
    .rddata    ( distree_rdata_fixed )
);

huffman_decode_symbol #(
    .NUMCODES  ( 32             ),
    .OUTWIDTH  ( 10             )
) distree_decoder (
    .rst       ( ~decoder_nreset),
    .clk       ( clk            ),
    .ien       ( distree_ien    ),
    .ibit      ( ibit           ),
    .oen       ( distree_codeen ),
    .ocode     ( distree_code   ),
    .rdaddr    ( distree_raddr  ),
    .rddata    ( fixed_tree ? distree_rdata_fixed : distree_rdata  )
);

repeat_buffer repeat_buffer_i(
    .clk          ( clk            ),
    
    .ivalid       ( symbol_valid   ),
    .idata        ( symbol         ),
    
    .repeat_en    ( irepeat        ),
    .repeat_start ( srepeat        ),
    .repeat_dist  ( distance       ),
    
    .ovalid       ( ovalid         ),
    .odata        ( obyte          )
);

endmodule


































module huffman_decode_symbol #(
    parameter    NUMCODES = 288,
    parameter    OUTWIDTH = 10
)(
    rst, clk,
    ien, ibit,
    oen, ocode,
    rdaddr, rddata
);

function automatic integer clogb2(input integer val);
    integer valtmp;
    valtmp = val;
    for(clogb2=0; valtmp>0; clogb2=clogb2+1) valtmp = valtmp>>1;
endfunction

input                               rst, clk;
input                               ien, ibit;
output                              oen = 1'b0;
output  [            OUTWIDTH-1:0]  ocode = '0;
output  [clogb2(2*NUMCODES-1)-1:0]  rdaddr;
input   [            OUTWIDTH-1:0]  rddata;

wire                              rst, clk;
wire                              ien, ibit;
reg                               oen = 1'b0;
reg  [            OUTWIDTH-1:0]   ocode = '0;
wire [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
wire [            OUTWIDTH-1:0]   rddata;

reg  [clogb2(2*NUMCODES-1)-2:0]   tpos = '0;
wire [clogb2(2*NUMCODES-1)-2:0]   ntpos;
reg                               ienl = 1'b0;

assign rdaddr = {ntpos, ibit};

assign ntpos = ienl ? (clogb2(2*NUMCODES-1)-1)'(rddata<(OUTWIDTH)'(NUMCODES) ? '0 : rddata-(OUTWIDTH)'(NUMCODES)) : tpos;

always @ (posedge clk or posedge rst)
    if(rst)
        ienl <= 1'b0;
    else
        ienl <= ien;

always @ (posedge clk or posedge rst)
    if(rst)
        tpos <= '0;
    else
        tpos <= ntpos;

always_comb
    if(ienl && rddata<NUMCODES) begin
        oen   <= 1'b1;
        ocode <= rddata;
    end else begin
        oen   <= 1'b0;
        ocode <= '0;
    end

endmodule

































module fixed_codetree (
  input  logic       clk,
  input  logic [9:0] rdaddr,
  output logic [9:0] rddata
);

wire [9:0] rom [1024]; assign rom[0]=10'd289; assign rom[1]=10'd370; assign rom[2]=10'd290; assign rom[3]=10'd307; assign rom[4]=10'd546; assign rom[5]=10'd291; assign rom[6]=10'd561; assign rom[7]=10'd292; assign rom[8]=10'd293; assign rom[9]=10'd300; assign rom[10]=10'd294; assign rom[11]=10'd297; assign rom[12]=10'd295; assign rom[13]=10'd296; assign rom[14]=10'd0; assign rom[15]=10'd1; assign rom[16]=10'd2; assign rom[17]=10'd3; assign rom[18]=10'd298; assign rom[19]=10'd299; assign rom[20]=10'd4; assign rom[21]=10'd5; assign rom[22]=10'd6; assign rom[23]=10'd7; assign rom[24]=10'd301; assign rom[25]=10'd304; assign rom[26]=10'd302; assign rom[27]=10'd303; assign rom[28]=10'd8; assign rom[29]=10'd9; assign rom[30]=10'd10; assign rom[31]=10'd11; assign rom[32]=10'd305; assign rom[33]=10'd306; assign rom[34]=10'd12; assign rom[35]=10'd13; assign rom[36]=10'd14; assign rom[37]=10'd15; assign rom[38]=10'd308; assign rom[39]=10'd339; assign rom[40]=10'd309; assign rom[41]=10'd324; assign rom[42]=10'd310; assign rom[43]=10'd317; assign rom[44]=10'd311; assign rom[45]=10'd314; assign rom[46]=10'd312; assign rom[47]=10'd313; assign rom[48]=10'd16; assign rom[49]=10'd17; assign rom[50]=10'd18; assign rom[51]=10'd19; assign rom[52]=10'd315; assign rom[53]=10'd316; assign rom[54]=10'd20; assign rom[55]=10'd21; assign rom[56]=10'd22; assign rom[57]=10'd23; assign rom[58]=10'd318; assign rom[59]=10'd321; assign rom[60]=10'd319; assign rom[61]=10'd320; assign rom[62]=10'd24; assign rom[63]=10'd25; assign rom[64]=10'd26; assign rom[65]=10'd27; assign rom[66]=10'd322; assign rom[67]=10'd323; assign rom[68]=10'd28; assign rom[69]=10'd29; assign rom[70]=10'd30; assign rom[71]=10'd31; assign rom[72]=10'd325; assign rom[73]=10'd332; assign rom[74]=10'd326; assign rom[75]=10'd329; assign rom[76]=10'd327; assign rom[77]=10'd328; assign rom[78]=10'd32; assign rom[79]=10'd33; assign rom[80]=10'd34; assign rom[81]=10'd35; assign rom[82]=10'd330; assign rom[83]=10'd331; assign rom[84]=10'd36; assign rom[85]=10'd37; assign rom[86]=10'd38; assign rom[87]=10'd39; assign rom[88]=10'd333; assign rom[89]=10'd336; assign rom[90]=10'd334; assign rom[91]=10'd335; assign rom[92]=10'd40; assign rom[93]=10'd41; assign rom[94]=10'd42; assign rom[95]=10'd43; assign rom[96]=10'd337; assign rom[97]=10'd338; assign rom[98]=10'd44; assign rom[99]=10'd45; assign rom[100]=10'd46; assign rom[101]=10'd47; assign rom[102]=10'd340; assign rom[103]=10'd355; assign rom[104]=10'd341; assign rom[105]=10'd348; assign rom[106]=10'd342; assign rom[107]=10'd345; assign rom[108]=10'd343; assign rom[109]=10'd344; assign rom[110]=10'd48; assign rom[111]=10'd49; assign rom[112]=10'd50; assign rom[113]=10'd51; assign rom[114]=10'd346; assign rom[115]=10'd347; assign rom[116]=10'd52; assign rom[117]=10'd53; assign rom[118]=10'd54; assign rom[119]=10'd55; assign rom[120]=10'd349; assign rom[121]=10'd352; assign rom[122]=10'd350; assign rom[123]=10'd351; assign rom[124]=10'd56; assign rom[125]=10'd57; assign rom[126]=10'd58; assign rom[127]=10'd59; assign rom[128]=10'd353; assign rom[129]=10'd354; assign rom[130]=10'd60; assign rom[131]=10'd61; assign rom[132]=10'd62; assign rom[133]=10'd63; assign rom[134]=10'd356; assign rom[135]=10'd363; assign rom[136]=10'd357; assign rom[137]=10'd360; assign rom[138]=10'd358; assign rom[139]=10'd359; assign rom[140]=10'd64; assign rom[141]=10'd65; assign rom[142]=10'd66; assign rom[143]=10'd67; assign rom[144]=10'd361; assign rom[145]=10'd362; assign rom[146]=10'd68; assign rom[147]=10'd69; assign rom[148]=10'd70; assign rom[149]=10'd71; assign rom[150]=10'd364; assign rom[151]=10'd367; assign rom[152]=10'd365; assign rom[153]=10'd366; assign rom[154]=10'd72; assign rom[155]=10'd73; assign rom[156]=10'd74; assign rom[157]=10'd75; assign rom[158]=10'd368; assign rom[159]=10'd369; assign rom[160]=10'd76; assign rom[161]=10'd77; assign rom[162]=10'd78; assign rom[163]=10'd79; assign rom[164]=10'd371; assign rom[165]=10'd434; assign rom[166]=10'd372; assign rom[167]=10'd403; assign rom[168]=10'd373; assign rom[169]=10'd388; assign rom[170]=10'd374; assign rom[171]=10'd381; assign rom[172]=10'd375; assign rom[173]=10'd378; assign rom[174]=10'd376; assign rom[175]=10'd377; assign rom[176]=10'd80; assign rom[177]=10'd81; assign rom[178]=10'd82; assign rom[179]=10'd83; assign rom[180]=10'd379; assign rom[181]=10'd380; assign rom[182]=10'd84; assign rom[183]=10'd85; assign rom[184]=10'd86; assign rom[185]=10'd87; assign rom[186]=10'd382; assign rom[187]=10'd385; assign rom[188]=10'd383; assign rom[189]=10'd384; assign rom[190]=10'd88; assign rom[191]=10'd89; assign rom[192]=10'd90; assign rom[193]=10'd91; assign rom[194]=10'd386; assign rom[195]=10'd387; assign rom[196]=10'd92; assign rom[197]=10'd93; assign rom[198]=10'd94; assign rom[199]=10'd95; assign rom[200]=10'd389; assign rom[201]=10'd396; assign rom[202]=10'd390; assign rom[203]=10'd393; assign rom[204]=10'd391; assign rom[205]=10'd392; assign rom[206]=10'd96; assign rom[207]=10'd97; assign rom[208]=10'd98; assign rom[209]=10'd99; assign rom[210]=10'd394; assign rom[211]=10'd395; assign rom[212]=10'd100; assign rom[213]=10'd101; assign rom[214]=10'd102; assign rom[215]=10'd103; assign rom[216]=10'd397; assign rom[217]=10'd400; assign rom[218]=10'd398; assign rom[219]=10'd399; assign rom[220]=10'd104; assign rom[221]=10'd105; assign rom[222]=10'd106; assign rom[223]=10'd107; assign rom[224]=10'd401; assign rom[225]=10'd402; assign rom[226]=10'd108; assign rom[227]=10'd109; assign rom[228]=10'd110; assign rom[229]=10'd111; assign rom[230]=10'd404; assign rom[231]=10'd419; assign rom[232]=10'd405; assign rom[233]=10'd412; assign rom[234]=10'd406; assign rom[235]=10'd409; assign rom[236]=10'd407; assign rom[237]=10'd408; assign rom[238]=10'd112; assign rom[239]=10'd113; assign rom[240]=10'd114; assign rom[241]=10'd115; assign rom[242]=10'd410; assign rom[243]=10'd411; assign rom[244]=10'd116; assign rom[245]=10'd117; assign rom[246]=10'd118; assign rom[247]=10'd119; assign rom[248]=10'd413; assign rom[249]=10'd416; assign rom[250]=10'd414; assign rom[251]=10'd415; assign rom[252]=10'd120; assign rom[253]=10'd121; assign rom[254]=10'd122; assign rom[255]=10'd123; assign rom[256]=10'd417; assign rom[257]=10'd418; assign rom[258]=10'd124; assign rom[259]=10'd125; assign rom[260]=10'd126; assign rom[261]=10'd127; assign rom[262]=10'd420; assign rom[263]=10'd427; assign rom[264]=10'd421; assign rom[265]=10'd424; assign rom[266]=10'd422; assign rom[267]=10'd423; assign rom[268]=10'd128; assign rom[269]=10'd129; assign rom[270]=10'd130; assign rom[271]=10'd131; assign rom[272]=10'd425; assign rom[273]=10'd426; assign rom[274]=10'd132; assign rom[275]=10'd133; assign rom[276]=10'd134; assign rom[277]=10'd135; assign rom[278]=10'd428; assign rom[279]=10'd431; assign rom[280]=10'd429; assign rom[281]=10'd430; assign rom[282]=10'd136; assign rom[283]=10'd137; assign rom[284]=10'd138; assign rom[285]=10'd139; assign rom[286]=10'd432; assign rom[287]=10'd433; assign rom[288]=10'd140; assign rom[289]=10'd141; assign rom[290]=10'd142; assign rom[291]=10'd143; assign rom[292]=10'd435; assign rom[293]=10'd483; assign rom[294]=10'd436; assign rom[295]=10'd452; assign rom[296]=10'd568; assign rom[297]=10'd437; assign rom[298]=10'd438; assign rom[299]=10'd445; assign rom[300]=10'd439; assign rom[301]=10'd442; assign rom[302]=10'd440; assign rom[303]=10'd441; assign rom[304]=10'd144; assign rom[305]=10'd145; assign rom[306]=10'd146; assign rom[307]=10'd147; assign rom[308]=10'd443; assign rom[309]=10'd444; assign rom[310]=10'd148; assign rom[311]=10'd149; assign rom[312]=10'd150; assign rom[313]=10'd151; assign rom[314]=10'd446; assign rom[315]=10'd449; assign rom[316]=10'd447; assign rom[317]=10'd448; assign rom[318]=10'd152; assign rom[319]=10'd153; assign rom[320]=10'd154; assign rom[321]=10'd155; assign rom[322]=10'd450; assign rom[323]=10'd451; assign rom[324]=10'd156; assign rom[325]=10'd157; assign rom[326]=10'd158; assign rom[327]=10'd159; assign rom[328]=10'd453; assign rom[329]=10'd468; assign rom[330]=10'd454; assign rom[331]=10'd461; assign rom[332]=10'd455; assign rom[333]=10'd458; assign rom[334]=10'd456; assign rom[335]=10'd457; assign rom[336]=10'd160; assign rom[337]=10'd161; assign rom[338]=10'd162; assign rom[339]=10'd163; assign rom[340]=10'd459; assign rom[341]=10'd460; assign rom[342]=10'd164; assign rom[343]=10'd165; assign rom[344]=10'd166; assign rom[345]=10'd167; assign rom[346]=10'd462; assign rom[347]=10'd465; assign rom[348]=10'd463; assign rom[349]=10'd464; assign rom[350]=10'd168; assign rom[351]=10'd169; assign rom[352]=10'd170; assign rom[353]=10'd171; assign rom[354]=10'd466; assign rom[355]=10'd467; assign rom[356]=10'd172; assign rom[357]=10'd173; assign rom[358]=10'd174; assign rom[359]=10'd175; assign rom[360]=10'd469; assign rom[361]=10'd476; assign rom[362]=10'd470; assign rom[363]=10'd473; assign rom[364]=10'd471; assign rom[365]=10'd472; assign rom[366]=10'd176; assign rom[367]=10'd177; assign rom[368]=10'd178; assign rom[369]=10'd179; assign rom[370]=10'd474; assign rom[371]=10'd475; assign rom[372]=10'd180; assign rom[373]=10'd181; assign rom[374]=10'd182; assign rom[375]=10'd183; assign rom[376]=10'd477; assign rom[377]=10'd480; assign rom[378]=10'd478; assign rom[379]=10'd479; assign rom[380]=10'd184; assign rom[381]=10'd185; assign rom[382]=10'd186; assign rom[383]=10'd187; assign rom[384]=10'd481; assign rom[385]=10'd482; assign rom[386]=10'd188; assign rom[387]=10'd189; assign rom[388]=10'd190; assign rom[389]=10'd191; assign rom[390]=10'd484; assign rom[391]=10'd515; assign rom[392]=10'd485; assign rom[393]=10'd500; assign rom[394]=10'd486; assign rom[395]=10'd493; assign rom[396]=10'd487; assign rom[397]=10'd490; assign rom[398]=10'd488; assign rom[399]=10'd489; assign rom[400]=10'd192; assign rom[401]=10'd193; assign rom[402]=10'd194; assign rom[403]=10'd195; assign rom[404]=10'd491; assign rom[405]=10'd492; assign rom[406]=10'd196; assign rom[407]=10'd197; assign rom[408]=10'd198; assign rom[409]=10'd199; assign rom[410]=10'd494; assign rom[411]=10'd497; assign rom[412]=10'd495; assign rom[413]=10'd496; assign rom[414]=10'd200; assign rom[415]=10'd201; assign rom[416]=10'd202; assign rom[417]=10'd203; assign rom[418]=10'd498; assign rom[419]=10'd499; assign rom[420]=10'd204; assign rom[421]=10'd205; assign rom[422]=10'd206; assign rom[423]=10'd207; assign rom[424]=10'd501; assign rom[425]=10'd508; assign rom[426]=10'd502; assign rom[427]=10'd505; assign rom[428]=10'd503; assign rom[429]=10'd504; assign rom[430]=10'd208; assign rom[431]=10'd209; assign rom[432]=10'd210; assign rom[433]=10'd211; assign rom[434]=10'd506; assign rom[435]=10'd507; assign rom[436]=10'd212; assign rom[437]=10'd213; assign rom[438]=10'd214; assign rom[439]=10'd215; assign rom[440]=10'd509; assign rom[441]=10'd512; assign rom[442]=10'd510; assign rom[443]=10'd511; assign rom[444]=10'd216; assign rom[445]=10'd217; assign rom[446]=10'd218; assign rom[447]=10'd219; assign rom[448]=10'd513; assign rom[449]=10'd514; assign rom[450]=10'd220; assign rom[451]=10'd221; assign rom[452]=10'd222; assign rom[453]=10'd223; assign rom[454]=10'd516; assign rom[455]=10'd531; assign rom[456]=10'd517; assign rom[457]=10'd524; assign rom[458]=10'd518; assign rom[459]=10'd521; assign rom[460]=10'd519; assign rom[461]=10'd520; assign rom[462]=10'd224; assign rom[463]=10'd225; assign rom[464]=10'd226; assign rom[465]=10'd227; assign rom[466]=10'd522; assign rom[467]=10'd523; assign rom[468]=10'd228; assign rom[469]=10'd229; assign rom[470]=10'd230; assign rom[471]=10'd231; assign rom[472]=10'd525; assign rom[473]=10'd528; assign rom[474]=10'd526; assign rom[475]=10'd527; assign rom[476]=10'd232; assign rom[477]=10'd233; assign rom[478]=10'd234; assign rom[479]=10'd235; assign rom[480]=10'd529; assign rom[481]=10'd530; assign rom[482]=10'd236; assign rom[483]=10'd237; assign rom[484]=10'd238; assign rom[485]=10'd239; assign rom[486]=10'd532; assign rom[487]=10'd539; assign rom[488]=10'd533; assign rom[489]=10'd536; assign rom[490]=10'd534; assign rom[491]=10'd535; assign rom[492]=10'd240; assign rom[493]=10'd241; assign rom[494]=10'd242; assign rom[495]=10'd243; assign rom[496]=10'd537; assign rom[497]=10'd538; assign rom[498]=10'd244; assign rom[499]=10'd245; assign rom[500]=10'd246; assign rom[501]=10'd247; assign rom[502]=10'd540; assign rom[503]=10'd543; assign rom[504]=10'd541; assign rom[505]=10'd542; assign rom[506]=10'd248; assign rom[507]=10'd249; assign rom[508]=10'd250; assign rom[509]=10'd251; assign rom[510]=10'd544; assign rom[511]=10'd545; assign rom[512]=10'd252; assign rom[513]=10'd253; assign rom[514]=10'd254; assign rom[515]=10'd255; assign rom[516]=10'd547; assign rom[517]=10'd554; assign rom[518]=10'd548; assign rom[519]=10'd551; assign rom[520]=10'd549; assign rom[521]=10'd550; assign rom[522]=10'd256; assign rom[523]=10'd257; assign rom[524]=10'd258; assign rom[525]=10'd259; assign rom[526]=10'd552; assign rom[527]=10'd553; assign rom[528]=10'd260; assign rom[529]=10'd261; assign rom[530]=10'd262; assign rom[531]=10'd263; assign rom[532]=10'd555; assign rom[533]=10'd558; assign rom[534]=10'd556; assign rom[535]=10'd557; assign rom[536]=10'd264; assign rom[537]=10'd265; assign rom[538]=10'd266; assign rom[539]=10'd267; assign rom[540]=10'd559; assign rom[541]=10'd560; assign rom[542]=10'd268; assign rom[543]=10'd269; assign rom[544]=10'd270; assign rom[545]=10'd271; assign rom[546]=10'd562; assign rom[547]=10'd565; assign rom[548]=10'd563; assign rom[549]=10'd564; assign rom[550]=10'd272; assign rom[551]=10'd273; assign rom[552]=10'd274; assign rom[553]=10'd275; assign rom[554]=10'd566; assign rom[555]=10'd567; assign rom[556]=10'd276; assign rom[557]=10'd277; assign rom[558]=10'd278; assign rom[559]=10'd279; assign rom[560]=10'd569; assign rom[561]=10'd572; assign rom[562]=10'd570; assign rom[563]=10'd571; assign rom[564]=10'd280; assign rom[565]=10'd281; assign rom[566]=10'd282; assign rom[567]=10'd283; assign rom[568]=10'd573; assign rom[569]=10'd574; assign rom[570]=10'd284; assign rom[571]=10'd285; assign rom[572]=10'd286; assign rom[573]=10'd287; assign rom[574]=10'd0; assign rom[575]=10'd0; assign rom[576]=10'd0; assign rom[577]=10'd0; assign rom[578]=10'd0; assign rom[579]=10'd0; assign rom[580]=10'd0; assign rom[581]=10'd0; assign rom[582]=10'd0; assign rom[583]=10'd0; assign rom[584]=10'd0; assign rom[585]=10'd0; assign rom[586]=10'd0; assign rom[587]=10'd0; assign rom[588]=10'd0; assign rom[589]=10'd0; assign rom[590]=10'd0; assign rom[591]=10'd0; assign rom[592]=10'd0; assign rom[593]=10'd0; assign rom[594]=10'd0; assign rom[595]=10'd0; assign rom[596]=10'd0; assign rom[597]=10'd0; assign rom[598]=10'd0; assign rom[599]=10'd0; assign rom[600]=10'd0; assign rom[601]=10'd0; assign rom[602]=10'd0; assign rom[603]=10'd0; assign rom[604]=10'd0; assign rom[605]=10'd0; assign rom[606]=10'd0; assign rom[607]=10'd0; assign rom[608]=10'd0; assign rom[609]=10'd0; assign rom[610]=10'd0; assign rom[611]=10'd0; assign rom[612]=10'd0; assign rom[613]=10'd0; assign rom[614]=10'd0; assign rom[615]=10'd0; assign rom[616]=10'd0; assign rom[617]=10'd0; assign rom[618]=10'd0; assign rom[619]=10'd0; assign rom[620]=10'd0; assign rom[621]=10'd0; assign rom[622]=10'd0; assign rom[623]=10'd0; assign rom[624]=10'd0; assign rom[625]=10'd0; assign rom[626]=10'd0; assign rom[627]=10'd0; assign rom[628]=10'd0; assign rom[629]=10'd0; assign rom[630]=10'd0; assign rom[631]=10'd0; assign rom[632]=10'd0; assign rom[633]=10'd0; assign rom[634]=10'd0; assign rom[635]=10'd0; assign rom[636]=10'd0; assign rom[637]=10'd0; assign rom[638]=10'd0; assign rom[639]=10'd0; assign rom[640]=10'd0; assign rom[641]=10'd0; assign rom[642]=10'd0; assign rom[643]=10'd0; assign rom[644]=10'd0; assign rom[645]=10'd0; assign rom[646]=10'd0; assign rom[647]=10'd0; assign rom[648]=10'd0; assign rom[649]=10'd0; assign rom[650]=10'd0; assign rom[651]=10'd0; assign rom[652]=10'd0; assign rom[653]=10'd0; assign rom[654]=10'd0; assign rom[655]=10'd0; assign rom[656]=10'd0; assign rom[657]=10'd0; assign rom[658]=10'd0; assign rom[659]=10'd0; assign rom[660]=10'd0; assign rom[661]=10'd0; assign rom[662]=10'd0; assign rom[663]=10'd0; assign rom[664]=10'd0; assign rom[665]=10'd0; assign rom[666]=10'd0; assign rom[667]=10'd0; assign rom[668]=10'd0; assign rom[669]=10'd0; assign rom[670]=10'd0; assign rom[671]=10'd0; assign rom[672]=10'd0; assign rom[673]=10'd0; assign rom[674]=10'd0; assign rom[675]=10'd0; assign rom[676]=10'd0; assign rom[677]=10'd0; assign rom[678]=10'd0; assign rom[679]=10'd0; assign rom[680]=10'd0; assign rom[681]=10'd0; assign rom[682]=10'd0; assign rom[683]=10'd0; assign rom[684]=10'd0; assign rom[685]=10'd0; assign rom[686]=10'd0; assign rom[687]=10'd0; assign rom[688]=10'd0; assign rom[689]=10'd0; assign rom[690]=10'd0; assign rom[691]=10'd0; assign rom[692]=10'd0; assign rom[693]=10'd0; assign rom[694]=10'd0; assign rom[695]=10'd0; assign rom[696]=10'd0; assign rom[697]=10'd0; assign rom[698]=10'd0; assign rom[699]=10'd0; assign rom[700]=10'd0; assign rom[701]=10'd0; assign rom[702]=10'd0; assign rom[703]=10'd0; assign rom[704]=10'd0; assign rom[705]=10'd0; assign rom[706]=10'd0; assign rom[707]=10'd0; assign rom[708]=10'd0; assign rom[709]=10'd0; assign rom[710]=10'd0; assign rom[711]=10'd0; assign rom[712]=10'd0; assign rom[713]=10'd0; assign rom[714]=10'd0; assign rom[715]=10'd0; assign rom[716]=10'd0; assign rom[717]=10'd0; assign rom[718]=10'd0; assign rom[719]=10'd0; assign rom[720]=10'd0; assign rom[721]=10'd0; assign rom[722]=10'd0; assign rom[723]=10'd0; assign rom[724]=10'd0; assign rom[725]=10'd0; assign rom[726]=10'd0; assign rom[727]=10'd0; assign rom[728]=10'd0; assign rom[729]=10'd0; assign rom[730]=10'd0; assign rom[731]=10'd0; assign rom[732]=10'd0; assign rom[733]=10'd0; assign rom[734]=10'd0; assign rom[735]=10'd0; assign rom[736]=10'd0; assign rom[737]=10'd0; assign rom[738]=10'd0; assign rom[739]=10'd0; assign rom[740]=10'd0; assign rom[741]=10'd0; assign rom[742]=10'd0; assign rom[743]=10'd0; assign rom[744]=10'd0; assign rom[745]=10'd0; assign rom[746]=10'd0; assign rom[747]=10'd0; assign rom[748]=10'd0; assign rom[749]=10'd0; assign rom[750]=10'd0; assign rom[751]=10'd0; assign rom[752]=10'd0; assign rom[753]=10'd0; assign rom[754]=10'd0; assign rom[755]=10'd0; assign rom[756]=10'd0; assign rom[757]=10'd0; assign rom[758]=10'd0; assign rom[759]=10'd0; assign rom[760]=10'd0; assign rom[761]=10'd0; assign rom[762]=10'd0; assign rom[763]=10'd0; assign rom[764]=10'd0; assign rom[765]=10'd0; assign rom[766]=10'd0; assign rom[767]=10'd0; assign rom[768]=10'd0; assign rom[769]=10'd0; assign rom[770]=10'd0; assign rom[771]=10'd0; assign rom[772]=10'd0; assign rom[773]=10'd0; assign rom[774]=10'd0; assign rom[775]=10'd0; assign rom[776]=10'd0; assign rom[777]=10'd0; assign rom[778]=10'd0; assign rom[779]=10'd0; assign rom[780]=10'd0; assign rom[781]=10'd0; assign rom[782]=10'd0; assign rom[783]=10'd0; assign rom[784]=10'd0; assign rom[785]=10'd0; assign rom[786]=10'd0; assign rom[787]=10'd0; assign rom[788]=10'd0; assign rom[789]=10'd0; assign rom[790]=10'd0; assign rom[791]=10'd0; assign rom[792]=10'd0; assign rom[793]=10'd0; assign rom[794]=10'd0; assign rom[795]=10'd0; assign rom[796]=10'd0; assign rom[797]=10'd0; assign rom[798]=10'd0; assign rom[799]=10'd0; assign rom[800]=10'd0; assign rom[801]=10'd0; assign rom[802]=10'd0; assign rom[803]=10'd0; assign rom[804]=10'd0; assign rom[805]=10'd0; assign rom[806]=10'd0; assign rom[807]=10'd0; assign rom[808]=10'd0; assign rom[809]=10'd0; assign rom[810]=10'd0; assign rom[811]=10'd0; assign rom[812]=10'd0; assign rom[813]=10'd0; assign rom[814]=10'd0; assign rom[815]=10'd0; assign rom[816]=10'd0; assign rom[817]=10'd0; assign rom[818]=10'd0; assign rom[819]=10'd0; assign rom[820]=10'd0; assign rom[821]=10'd0; assign rom[822]=10'd0; assign rom[823]=10'd0; assign rom[824]=10'd0; assign rom[825]=10'd0; assign rom[826]=10'd0; assign rom[827]=10'd0; assign rom[828]=10'd0; assign rom[829]=10'd0; assign rom[830]=10'd0; assign rom[831]=10'd0; assign rom[832]=10'd0; assign rom[833]=10'd0; assign rom[834]=10'd0; assign rom[835]=10'd0; assign rom[836]=10'd0; assign rom[837]=10'd0; assign rom[838]=10'd0; assign rom[839]=10'd0; assign rom[840]=10'd0; assign rom[841]=10'd0; assign rom[842]=10'd0; assign rom[843]=10'd0; assign rom[844]=10'd0; assign rom[845]=10'd0; assign rom[846]=10'd0; assign rom[847]=10'd0; assign rom[848]=10'd0; assign rom[849]=10'd0; assign rom[850]=10'd0; assign rom[851]=10'd0; assign rom[852]=10'd0; assign rom[853]=10'd0; assign rom[854]=10'd0; assign rom[855]=10'd0; assign rom[856]=10'd0; assign rom[857]=10'd0; assign rom[858]=10'd0; assign rom[859]=10'd0; assign rom[860]=10'd0; assign rom[861]=10'd0; assign rom[862]=10'd0; assign rom[863]=10'd0; assign rom[864]=10'd0; assign rom[865]=10'd0; assign rom[866]=10'd0; assign rom[867]=10'd0; assign rom[868]=10'd0; assign rom[869]=10'd0; assign rom[870]=10'd0; assign rom[871]=10'd0; assign rom[872]=10'd0; assign rom[873]=10'd0; assign rom[874]=10'd0; assign rom[875]=10'd0; assign rom[876]=10'd0; assign rom[877]=10'd0; assign rom[878]=10'd0; assign rom[879]=10'd0; assign rom[880]=10'd0; assign rom[881]=10'd0; assign rom[882]=10'd0; assign rom[883]=10'd0; assign rom[884]=10'd0; assign rom[885]=10'd0; assign rom[886]=10'd0; assign rom[887]=10'd0; assign rom[888]=10'd0; assign rom[889]=10'd0; assign rom[890]=10'd0; assign rom[891]=10'd0; assign rom[892]=10'd0; assign rom[893]=10'd0; assign rom[894]=10'd0; assign rom[895]=10'd0; assign rom[896]=10'd0; assign rom[897]=10'd0; assign rom[898]=10'd0; assign rom[899]=10'd0; assign rom[900]=10'd0; assign rom[901]=10'd0; assign rom[902]=10'd0; assign rom[903]=10'd0; assign rom[904]=10'd0; assign rom[905]=10'd0; assign rom[906]=10'd0; assign rom[907]=10'd0; assign rom[908]=10'd0; assign rom[909]=10'd0; assign rom[910]=10'd0; assign rom[911]=10'd0; assign rom[912]=10'd0; assign rom[913]=10'd0; assign rom[914]=10'd0; assign rom[915]=10'd0; assign rom[916]=10'd0; assign rom[917]=10'd0; assign rom[918]=10'd0; assign rom[919]=10'd0; assign rom[920]=10'd0; assign rom[921]=10'd0; assign rom[922]=10'd0; assign rom[923]=10'd0; assign rom[924]=10'd0; assign rom[925]=10'd0; assign rom[926]=10'd0; assign rom[927]=10'd0; assign rom[928]=10'd0; assign rom[929]=10'd0; assign rom[930]=10'd0; assign rom[931]=10'd0; assign rom[932]=10'd0; assign rom[933]=10'd0; assign rom[934]=10'd0; assign rom[935]=10'd0; assign rom[936]=10'd0; assign rom[937]=10'd0; assign rom[938]=10'd0; assign rom[939]=10'd0; assign rom[940]=10'd0; assign rom[941]=10'd0; assign rom[942]=10'd0; assign rom[943]=10'd0; assign rom[944]=10'd0; assign rom[945]=10'd0; assign rom[946]=10'd0; assign rom[947]=10'd0; assign rom[948]=10'd0; assign rom[949]=10'd0; assign rom[950]=10'd0; assign rom[951]=10'd0; assign rom[952]=10'd0; assign rom[953]=10'd0; assign rom[954]=10'd0; assign rom[955]=10'd0; assign rom[956]=10'd0; assign rom[957]=10'd0; assign rom[958]=10'd0; assign rom[959]=10'd0; assign rom[960]=10'd0; assign rom[961]=10'd0; assign rom[962]=10'd0; assign rom[963]=10'd0; assign rom[964]=10'd0; assign rom[965]=10'd0; assign rom[966]=10'd0; assign rom[967]=10'd0; assign rom[968]=10'd0; assign rom[969]=10'd0; assign rom[970]=10'd0; assign rom[971]=10'd0; assign rom[972]=10'd0; assign rom[973]=10'd0; assign rom[974]=10'd0; assign rom[975]=10'd0; assign rom[976]=10'd0; assign rom[977]=10'd0; assign rom[978]=10'd0; assign rom[979]=10'd0; assign rom[980]=10'd0; assign rom[981]=10'd0; assign rom[982]=10'd0; assign rom[983]=10'd0; assign rom[984]=10'd0; assign rom[985]=10'd0; assign rom[986]=10'd0; assign rom[987]=10'd0; assign rom[988]=10'd0; assign rom[989]=10'd0; assign rom[990]=10'd0; assign rom[991]=10'd0; assign rom[992]=10'd0; assign rom[993]=10'd0; assign rom[994]=10'd0; assign rom[995]=10'd0; assign rom[996]=10'd0; assign rom[997]=10'd0; assign rom[998]=10'd0; assign rom[999]=10'd0; assign rom[1000]=10'd0; assign rom[1001]=10'd0; assign rom[1002]=10'd0; assign rom[1003]=10'd0; assign rom[1004]=10'd0; assign rom[1005]=10'd0; assign rom[1006]=10'd0; assign rom[1007]=10'd0; assign rom[1008]=10'd0; assign rom[1009]=10'd0; assign rom[1010]=10'd0; assign rom[1011]=10'd0; assign rom[1012]=10'd0; assign rom[1013]=10'd0; assign rom[1014]=10'd0; assign rom[1015]=10'd0; assign rom[1016]=10'd0; assign rom[1017]=10'd0; assign rom[1018]=10'd0; assign rom[1019]=10'd0; assign rom[1020]=10'd0; assign rom[1021]=10'd0; assign rom[1022]=10'd0; assign rom[1023]=10'd0;

always @ (posedge clk)
    rddata <= rom[rdaddr];

endmodule

























module fixed_distree (
  input  logic       clk,
  input  logic [5:0] rdaddr,
  output logic [9:0] rddata
);

wire [9:0] rom [64]; assign rom[0]=10'd33; assign rom[1]=10'd48; assign rom[2]=10'd34; assign rom[3]=10'd41; assign rom[4]=10'd35; assign rom[5]=10'd38; assign rom[6]=10'd36; assign rom[7]=10'd37; assign rom[8]=10'd0; assign rom[9]=10'd1; assign rom[10]=10'd2; assign rom[11]=10'd3; assign rom[12]=10'd39; assign rom[13]=10'd40; assign rom[14]=10'd4; assign rom[15]=10'd5; assign rom[16]=10'd6; assign rom[17]=10'd7; assign rom[18]=10'd42; assign rom[19]=10'd45; assign rom[20]=10'd43; assign rom[21]=10'd44; assign rom[22]=10'd8; assign rom[23]=10'd9; assign rom[24]=10'd10; assign rom[25]=10'd11; assign rom[26]=10'd46; assign rom[27]=10'd47; assign rom[28]=10'd12; assign rom[29]=10'd13; assign rom[30]=10'd14; assign rom[31]=10'd15; assign rom[32]=10'd49; assign rom[33]=10'd56; assign rom[34]=10'd50; assign rom[35]=10'd53; assign rom[36]=10'd51; assign rom[37]=10'd52; assign rom[38]=10'd16; assign rom[39]=10'd17; assign rom[40]=10'd18; assign rom[41]=10'd19; assign rom[42]=10'd54; assign rom[43]=10'd55; assign rom[44]=10'd20; assign rom[45]=10'd21; assign rom[46]=10'd22; assign rom[47]=10'd23; assign rom[48]=10'd57; assign rom[49]=10'd60; assign rom[50]=10'd58; assign rom[51]=10'd59; assign rom[52]=10'd24; assign rom[53]=10'd25; assign rom[54]=10'd26; assign rom[55]=10'd27; assign rom[56]=10'd61; assign rom[57]=10'd62; assign rom[58]=10'd28; assign rom[59]=10'd29; assign rom[60]=10'd30; assign rom[61]=10'd31; assign rom[62]=10'd0; assign rom[63]=10'd0;

always @ (posedge clk)
    rddata <= rom[rdaddr];

endmodule



















module huffman_build #(
    parameter NUMCODES = 288,
    parameter CODEBITS = 5,
    parameter BITLENGTH= 15,
    parameter OUTWIDTH = 10
) (
    clk,
    wren, wraddr, wrdata,
    run , done,
    rdaddr, rddata
);

function automatic integer clogb2(input integer val);
    integer valtmp;
    valtmp = val;
    for(clogb2=0; valtmp>0; clogb2=clogb2+1) valtmp = valtmp>>1;
endfunction

input                               clk;
input                               wren;
input  [  clogb2(NUMCODES-1)-1:0]   wraddr;
input  [           CODEBITS -1:0]   wrdata;
input                               run;
output                              done;
input  [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
output [            OUTWIDTH-1:0]   rddata;

wire                              clk;
wire                              wren;
wire [  clogb2(NUMCODES-1)-1:0]   wraddr;
wire [           CODEBITS -1:0]   wrdata;
wire                              run;
wire                              done;
wire [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
wire [            OUTWIDTH-1:0]   rddata;

reg  [clogb2(NUMCODES)-1:0] blcount  [BITLENGTH];
reg  [                31:0] nextcode [BITLENGTH+1];

reg  clear_tree2d = 1'b0;
reg  build_tree2d = 1'b0;
reg  [clogb2(BITLENGTH)-1:0] idx = '0;
reg  [clogb2(2*NUMCODES+1)-1:0] clearidx = '0;
reg  [ clogb2(NUMCODES)-1:0] nn='0, nnn, lnn='0;
reg  [CODEBITS-1:0] ii='0, lii='0;
reg  [CODEBITS-1:0] blenn, blen = '0;
wire [31:0] tree1d = nextcode[blen];
wire        islast = (blen==0 || ii==0);
reg  [clogb2(2*NUMCODES-1)-1:0] nodefilled = '0;
reg  [clogb2(2*NUMCODES-1)-1:0] ntreepos, treepos='0;
wire [clogb2(2*NUMCODES-1)  :0] ntpos= {ntreepos, tree1d[ii]};
reg  [clogb2(2*NUMCODES-1)  :0] tpos = '0;
wire        rdfilled;
reg         valid = 1'b0;
wire [OUTWIDTH-1:0] wrtree2d = (lii==0) ? lnn : nodefilled + (clogb2(2*NUMCODES-1))'(NUMCODES);
reg  alldone = 1'b0;

assign done = alldone & run;

initial for(int i=0; i< BITLENGTH; i++) blcount[i] = '0;
initial for(int i=0; i<=BITLENGTH; i++) nextcode[i] = '0;

always @ (posedge clk) begin
    valid <= build_tree2d & nn<NUMCODES & blen>0;
    treepos <= ntreepos;
    tpos <= ntpos;
    lii <= ii;
    lnn <= nn;
end

always @ (posedge clk)
    if(islast)
        blen <= blenn;

always @ (posedge clk)
    if(done) begin
        for(int i=0; i<BITLENGTH; i++)
            blcount[i] <= '0;
    end else begin
        if(wren && wrdata<BITLENGTH)
            blcount[wrdata] <= blcount[wrdata] + (clogb2(NUMCODES))'(1);
    end

always_comb
    if(build_tree2d)
        nnn <= (nn<NUMCODES && islast) ? nn + (clogb2(NUMCODES))'(1) : nn;
    else
        nnn <= (idx<BITLENGTH) ? '1 : '0;
        
always @ (posedge clk)
    nn <= nnn;

always @ (posedge clk) begin
    nextcode[0] <= 0;
    alldone <= 1'b0;
    if(run) begin
        if(~clear_tree2d) begin
            if(clearidx<(2*NUMCODES)) begin
                clearidx <= clearidx + (clogb2(2*NUMCODES+1))'(1);
            end else begin
                clear_tree2d <= 1'b1;
            end
        end else if(build_tree2d) begin
            if(nn<NUMCODES) begin
                if(islast) begin
                    ii <= blenn - (CODEBITS)'(1);
                    if(blen>0)
                        nextcode[blen] <= tree1d + 1;
                end else
                    ii <= ii - (CODEBITS)'(1);
            end else
                alldone <= 1'b1;
        end else begin
            if(idx<BITLENGTH) begin
                idx <= idx + (clogb2(BITLENGTH))'(1);
                nextcode[idx+1] <= ( (nextcode[idx] + blcount[idx]) << 1 );
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
        ntreepos <= 0;
    else if(valid) begin
        if(~rdfilled)
            ntreepos <= (clogb2(2*NUMCODES-1))'(rddata) - (clogb2(2*NUMCODES-1))'(NUMCODES);
        else
            ntreepos <= (lii==0) ? '0 : nodefilled;
    end else
        ntreepos <= treepos;
    
always @ (posedge clk)
    if(~run)
        nodefilled <= 1;
    else if(valid & rdfilled & lii>0)
        nodefilled <= nodefilled + (clogb2(2*NUMCODES-1))'(1);

RamSinglePort #(
    .SIZE     ( NUMCODES    ),
    .WIDTH    ( CODEBITS    )
) ram_for_bitlens (
    .clk      ( clk         ),
    .wen      ( wren        ),
    .waddr    ( wraddr      ),
    .wdata    ( wrdata      ),
    .raddr    ( (clogb2(NUMCODES-1))'(nnn) + (clogb2(NUMCODES-1))'(1)     ),
    .rdata    ( blenn       )
);

RamSinglePort #(
    .SIZE     ( NUMCODES * 2              ),
    .WIDTH    ( OUTWIDTH + 1              )
) ram_for_tree2d (
    .clk      ( clk                       ),
    .wen      ( clearidx<(2*NUMCODES)   |  (valid & rdfilled)                        ),
    .waddr    ( (clogb2(2*NUMCODES-1))'(clearidx<(2*NUMCODES) ? clearidx : tpos )    ),
    .wdata    ( clearidx<(2*NUMCODES)   ? {1'b1,{OUTWIDTH{1'b0}}} : {1'b0, wrtree2d} ),
    .raddr    ( (clogb2(2*NUMCODES-1))'(alldone               ? rdaddr   : ntpos  )  ),
    .rdata    ( {rdfilled, rddata}        )
);

endmodule

















module repeat_buffer #(
    parameter            DWIDTH = 8
) (
    input                    clk,
    
    input                    ivalid,
    input      [DWIDTH-1:0]  idata,
    
    input                    repeat_en,
    input                    repeat_start,
    input      [      15:0]  repeat_dist,
    
    output                   ovalid,
    output     [DWIDTH-1:0]  odata
);

wire [15:0]  MAXLEN = 16'd33792;

reg  [15:0]  wptr = '0;
reg  [15:0]  rptr = '0;
reg  [15:0]  sptr = '0;
reg  [15:0]  eptr = '0;
wire [15:0]  sptrw = (wptr<repeat_dist) ? wptr + MAXLEN - repeat_dist : wptr - repeat_dist;
wire [15:0]  eptrw = (wptr<16'd1) ? wptr + MAXLEN - 16'd1 : wptr - 16'd1;

reg                repeat_valid = 1'b0;
wire [DWIDTH-1:0]  repeat_data;

assign  ovalid = ivalid | repeat_valid;
assign  odata  = repeat_valid ? repeat_data : idata;

always @ (posedge clk)
    if(ovalid)
        wptr <= (wptr<(MAXLEN-16'd1)) ? wptr+16'd1 : '0;

always @ (posedge clk) begin
    if(repeat_start) begin
        rptr <= sptrw;
        sptr <= sptrw;
        eptr <= eptrw;
    end else if(repeat_en) begin
        if(rptr!=eptr)
            rptr <= (rptr<(MAXLEN-16'd1)) ? rptr+16'd1 : '0;
        else
            rptr <= sptr;
    end
end

always @ (posedge clk)
    repeat_valid <= repeat_en;

RamSinglePort #(
    .SIZE     ( 33792       ),
    .WIDTH    ( DWIDTH      )
) ram_for_bitlens (
    .clk      ( clk         ),
    .wen      ( ovalid      ),
    .waddr    ( wptr        ),
    .wdata    ( odata       ),
    .raddr    ( rptr        ),
    .rdata    ( repeat_data )
);

endmodule
































module unfilter(
    input wire         rst,
    input wire         clk,
    // config parameter
    input wire [ 1:0]  bpp,  // bytes per pixel (-1)
    input wire [13:0]  bpr,  // bytes per row
    // data input
    input wire         ivalid,
    input wire [ 7:0]  idata,
    // data output
    output reg         ovalid,
    output reg [ 7:0]  odata
);

initial ovalid = 1'b0;
initial odata  = '0;

function automatic logic [7:0] paeth(input [7:0] a, input [7:0] b, input [7:0] c);
    automatic logic signed [10:0] sa = {3'h0, a};
    automatic logic signed [10:0] sb = {3'h0, b};
    automatic logic signed [10:0] sc = {3'h0, c};
	automatic logic signed [10:0] p  = sa + sb - sc;
	automatic logic signed [10:0] pa = p > sa ? p - sa : sa - p;
	automatic logic signed [10:0] pb = p > sb ? p - sb : sb - p;
	automatic logic signed [10:0] pc = p > sc ? p - sc : sc - p;
	if (pa <= pb && pa <= pc)
		return a;
	else if (pb <= pc)
		return b;
	else
		return c;
endfunction

reg         nfirstrow = 1'b0;
reg  [13:0] col = '0;
reg  [ 2:0] mode = '0;
reg  [ 7:0] fdata;
wire [ 7:0] LLdata, UUdata, ULdata;
wire nfirstcol  = col > (14'h1+bpp);
wire [ 8:0] SSdata = (nfirstcol ? {1'b0,LLdata} : 9'h0) + (nfirstrow ? {1'b0,UUdata} : 9'h0);


always @ (posedge clk or posedge rst)
    if(rst) begin
        nfirstrow <= 1'b0;
        col       <= '0;
    end else begin
        if(ivalid) begin
            if(col<bpr) begin
                col <= col + 14'h1;
            end else begin
                nfirstrow <= 1'b1;
                col <= '0;
            end
        end
    end

always @ (posedge clk or posedge rst)
    if(rst)
        mode <= '0;
    else begin
        if(ivalid && col==14'h0)
            mode <= idata[2:0];
    end

always_comb
    case(mode)
    3'd0   : fdata <= idata;
    3'd1   : fdata <= idata + (nfirstcol ? LLdata : 8'h0);
    3'd2   : fdata <= idata + (nfirstrow ? UUdata : 8'h0);
    3'd3   : fdata <= idata + SSdata[8:1];
    default: fdata <= idata + paeth(
                                        (nfirstcol ? LLdata : 8'h0),
                                        (nfirstrow ? UUdata : 8'h0),
                                        (nfirstrow&nfirstcol ? ULdata : 8'h0)
                                   );
    endcase

always @ (posedge clk or posedge rst)
    if(rst) begin
        ovalid <= 1'b0;
        odata  <= '0;
    end else begin
        ovalid <= (ivalid && col!=14'h0);
        if(ivalid && col!=14'h0)
            odata <= fdata;
    end

shift_regs #(
    .MAXLEN_LEVEL ( 2         ),
    .DWIDTH       ( 8         )
) shift_i1 (
    .rst          ( rst       ),
    .clk          ( clk       ),
    .length       ( bpp       ),
    .ivalid       ( ivalid    ),
    .idata        ( fdata     ),
    .odata        ( LLdata    )
);

shift_buffer #(
    .MAXLEN_LEVEL ( 14        ),
    .DWIDTH       ( 8         )
) shift_i2 (
    .rst          ( rst       ),
    .clk          ( clk       ),
    .length       ( bpr       ),
    .ivalid       ( ivalid    ),
    .idata        ( fdata     ),
    .odata        ( UUdata    )
);

shift_regs #(
    .MAXLEN_LEVEL ( 2         ),
    .DWIDTH       ( 8         )
) shift_i3 (
    .rst          ( rst       ),
    .clk          ( clk       ),
    .length       ( bpp       ),
    .ivalid       ( ivalid    ),
    .idata        ( UUdata    ),
    .odata        ( ULdata    )
);

endmodule


































module shift_buffer #(
    parameter                      MAXLEN_LEVEL = 14,
    parameter                      DWIDTH       = 8
) (
    input                          rst,
    input                          clk,
    
    input      [MAXLEN_LEVEL-1:0]  length,  // length = 1 ~ (1<<MAXLEN_LEVEL)
    
    input                          ivalid,
    input      [      DWIDTH-1:0]  idata,

    output     [      DWIDTH-1:0]  odata
);

localparam MAXLEN = 1<<MAXLEN_LEVEL;

reg                     rvalid = 1'b0;
wire [      DWIDTH-1:0] rdata;
reg  [      DWIDTH-1:0] ldata = '0;
reg  [      DWIDTH-1:0] lidata= '0;
reg  [MAXLEN_LEVEL-1:0] ptr = '0;

always @ (posedge clk or posedge rst)
    if(rst)
        lidata <= '0;
    else begin
        if(ivalid)
            lidata <= idata;
    end

always @ (posedge clk or posedge rst)
    if(rst)
        ptr <= '0;
    else begin
        if(ivalid) begin
            if(ptr<(length-1))
                ptr <= ptr + (MAXLEN_LEVEL)'(1);
            else
                ptr <= '0;
        end
    end

always @ (posedge clk or posedge rst)
    if(rst) begin
        ldata  <= '0;
        rvalid <= 1'b0;
    end else begin
        if(rvalid)
            ldata <= rdata;
        rvalid <= ivalid;
    end
    
assign odata = (length=='0) ? lidata : (rvalid ? rdata : ldata);

RamSinglePort #(
    .SIZE     ( MAXLEN      ),
    .WIDTH    ( DWIDTH      )
) ram_for_bitlens (
    .clk      ( clk         ),
    .wen      ( ivalid      ),
    .waddr    ( ptr         ),
    .wdata    ( idata       ),
    .raddr    ( ptr         ),
    .rdata    ( rdata       )
);

endmodule


















module shift_regs #(
    parameter                      MAXLEN_LEVEL = 2,
    parameter                      DWIDTH       = 8
) (
    input                          rst,
    input                          clk,
    
    input      [MAXLEN_LEVEL-1:0]  length,  // length = 1~(1<<MAXLEN_LEVEL)
    
    input                          ivalid,
    input      [      DWIDTH-1:0]  idata,

    output     [      DWIDTH-1:0]  odata
);

localparam MAXLEN = 1<<MAXLEN_LEVEL;

reg [DWIDTH-1:0] shift_data [MAXLEN] = '{MAXLEN{'0}};

assign odata  = shift_data [length];

generate
    genvar ii;
    for(ii=0; ii<MAXLEN; ii++) begin : generate_shift_registers
        if(ii==0) begin
            always @ (posedge clk or posedge rst)
                if(rst) begin
                    shift_data[ii]  <= '0;
                end else begin
                    if(ivalid)
                        shift_data[ii] <= idata;
                end
        end else begin
            always @ (posedge clk or posedge rst)
                if(rst) begin
                    shift_data[ii]  <= '0;
                end else begin
                    if(ivalid)
                        shift_data[ii] <= shift_data[ii-1];
                end
        end
    end
endgenerate

endmodule




















module RamSinglePort #(
    parameter  SIZE     = 1024,
    parameter  WIDTH    = 32
)(
    clk,
    wen,
    waddr,
    wdata,
    raddr,
    rdata
);

function automatic integer clogb2(input integer val);
    integer valtmp;
    valtmp = val;
    for(clogb2=0; valtmp>0; clogb2=clogb2+1) valtmp = valtmp>>1;
endfunction

input  clk;
input  wen;
input  [clogb2(SIZE-1)-1:0] waddr;
input  [WIDTH-1:0] wdata;
input  [clogb2(SIZE-1)-1:0] raddr;
output [WIDTH-1:0] rdata;

wire  clk;
wire  wen;
wire  [clogb2(SIZE-1)-1:0] waddr;
wire  [WIDTH-1:0] wdata;
wire  [clogb2(SIZE-1)-1:0] raddr;
reg   [WIDTH-1:0] rdata;

reg [WIDTH-1:0] mem [SIZE];

always @ (posedge clk)
    if(wen)
        mem[waddr] <= wdata;

initial rdata = '0;
always @ (posedge clk)
    rdata <= mem[raddr];

endmodule
