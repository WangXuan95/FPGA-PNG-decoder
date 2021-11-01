`timescale 1 ns/1 ns

`define PNG_FILE "E:/FPGAcommon/Hard-PNG/images/test14.png"   // the png file to decode
`define OUT_FILE "E:/FPGAcommon/Hard-PNG/result/test14.txt"   // decode result txt file
`define OUT_ENABLE 1                                          // whether to write result to the decode result txt file

module tb_hard_png();

integer fppng, fptxt;
reg [7:0] rbyte;

reg rst = 1'b1;
reg clk = 1'b1;
always #5 clk = ~clk;

reg          ivalid = 1'b0;
wire         iready;
reg  [ 7:0]  ibyte = '0;

wire         newframe;
wire [ 1:0]  colortype;
wire [13:0]  width;
wire [31:0]  height;

wire         ovalid;
wire [ 7:0]  opixelr, opixelg, opixelb, opixela;


initial begin
    fppng = $fopen(`PNG_FILE, "rb");
    if(`OUT_ENABLE) fptxt = $fopen(`OUT_FILE, "w");
    rbyte = $fgetc(fppng);
    
    @(posedge clk) rst = 1'b1;
    @(posedge clk) rst = 1'b0;
        
    @(posedge clk) #1
    ivalid <= 1'b0;
    ibyte  <= 1'b0;

    while(!$feof(fppng)) begin
        @(posedge clk) #1
        ivalid <= 1'b1;
        ibyte  <= rbyte;
        #1 if(iready) begin
            rbyte = $fgetc(fppng);
            //@(posedge clk) #1
            //ivalid <= 1'b0;
            //ibyte  <= '0;
        end
    end
    
    @(posedge clk) #1
    ivalid <= 1'b0;
    ibyte  <= 1'b0;

    $fclose(fppng);
    if(`OUT_ENABLE) $fclose(fptxt);
end

hard_png hard_png_i(
    .rst       ( rst       ),
    .clk       ( clk       ),
    // data input
    .ivalid    ( ivalid    ),
    .iready    ( iready    ),
    .ibyte     ( ibyte     ),
    // image size output
    .newframe  ( newframe  ),
    .colortype ( colortype ),
    .width     ( width     ),
    .height    ( height    ),
    // data output
    .ovalid    ( ovalid    ),
    .opixelr   ( opixelr   ),
    .opixelg   ( opixelg   ),
    .opixelb   ( opixelb   ),
    .opixela   ( opixela   )
);

reg [31:0] pixcnt = 0;

always @ (posedge clk)
    if(newframe) begin
        pixcnt <= 0;
        if(`OUT_ENABLE)
            $fwrite(fptxt, "\nframe  type:%1d  width:%1d  height:%1d\n", colortype, width, height);
        else
            $write("\nframe  type:%1d  width:%1d  height:%1d\n", colortype, width, height);
    end else if(ovalid) begin
        pixcnt <= pixcnt + 1;
        if(`OUT_ENABLE) $fwrite(fptxt, "%02x%02x%02x%02x ", opixelr, opixelg, opixelb, opixela);
    end

endmodule
