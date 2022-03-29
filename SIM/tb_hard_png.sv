
//--------------------------------------------------------------------------------------------------------
// Module  : tb_hard_png
// Type    : simulation, top
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: testbench for hard_png
//--------------------------------------------------------------------------------------------------------

`timescale 1ps/1ps


`define START_NO  1      // first png file number to decode
`define FINAL_NO  14     // last png file number to decode

`define IN_PNG_FILE_FOMRAT    "test_image/img%02d.png"
`define OUT_TXT_FILE_FORMAT   "out%02d.txt"


module tb_hard_png ();

initial $dumpvars(1, tb_hard_png);


reg rstn = 1'b0;
reg clk  = 1'b1;
always  #10000 clk = ~clk;    // 50MHz


reg  [ 7:0]  ibyte = '0;
reg          ivalid = 1'b0;
wire         iready;

wire         newframe;
wire [ 2:0]  colortype;
wire [13:0]  width;
wire [31:0]  height;

wire         ovalid;
wire [ 7:0]  opixelr, opixelg, opixelb, opixela;



hard_png hard_png_i (
    .rstn      ( rstn      ),
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



int fptxt = 0, fppng = 0;
reg [256*8:1] fname_png;
reg [256*8:1] fname_txt;
int png_no = 0;
int txt_no = 0;

int cyccnt = 0;
int bytecnt = 1;

initial begin
    fork
        // thread: input png file
        for(png_no=`START_NO; png_no<=`FINAL_NO; png_no=png_no+1) begin
            @ (posedge clk);
            rstn <= 1'b1;
            
            $sformat(fname_png, `IN_PNG_FILE_FOMRAT , png_no);
            
            fppng = $fopen(fname_png, "rb");
            if(fppng == 0) begin
                $error("input file %s open failed", fname_png);
                $finish;
            end
            cyccnt = 0;
            bytecnt = 1;
            
            $display("start to decode %30s", fname_png );
            
            ibyte <= $fgetc(fppng);
            while( !$feof(fppng) ) @(posedge clk) begin
                if(~ivalid | iready ) begin
                    ivalid <= 1'b1;                   // use this to always try to input a byte to hard_png (no bubble, will get maximum throughput)
                    //ivalid <= ($random % 3) == 0;     // use this to add random bubbles to the input stream of hard_png. (Although the maximum throughput cannot be achieved, it allows input with mismatched rate, which is more common in the actual engineering scenarios)
                end
                if( ivalid & iready ) begin
                    ibyte <= $fgetc(fppng);
                    bytecnt++;
                end
                cyccnt++;
            end
            ivalid <= 1'b0;
            rstn <= 1'b0;
            
            $fclose(fppng);
            $display("image %30s decode done, input %d bytes in %d cycles, throughput=%f byte/cycle", fname_png, bytecnt, cyccnt, (1.0*bytecnt)/cyccnt );
        end
        
        
        // thread: output txt file
        for(txt_no=`START_NO; txt_no<=`FINAL_NO; txt_no=txt_no+1) begin
            $sformat(fname_txt, `OUT_TXT_FILE_FORMAT , txt_no);
        
            while(~newframe) @ (posedge clk);
            $display("decode result:  colortype:%1d  width:%1d  height:%1d", colortype, width, height);
            
            fptxt = $fopen(fname_txt, "w");
            if(fptxt != 0)
                $fwrite(fptxt, "decode result:  colortype:%1d  width:%1d  height:%1d\n", colortype, width, height);
            else begin
                $error("output txt file %30s open failed", fname_txt);
                $finish;
            end
            
            for(int ii=0; ii<width*height; ii++) begin
                @ (posedge clk);
                while(~ovalid) @ (posedge clk);
                $fwrite(fptxt, "%02x%02x%02x%02x ", opixelr, opixelg, opixelb, opixela);
                if( (ii % (width*height/10)) == 0 ) $display("%d/%d", ii, width*height);
            end
            
            $fclose(fptxt);
        end
    join
    
    repeat(100) @ (posedge clk);
    $finish;
end


endmodule
