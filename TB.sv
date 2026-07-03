module TB;
  parameter bit [1:0] spi_mode = 2'b10;
    spi_if spi_vif();   // instantiate interface here

  spi_master #(.SPI_MODE(spi_mode)) dut (
        .i_Clk(spi_vif.i_Clk),
        .i_Rst_L(spi_vif.i_Rst_L),
        .i_TX_Byte(spi_vif.i_TX_Byte),
        .i_TX_DV(spi_vif.i_TX_DV),
        .o_TX_Ready(spi_vif.o_TX_Ready),
        .o_RX_DV(spi_vif.o_RX_DV),
        .o_RX_Byte(spi_vif.o_RX_Byte),
        .o_SPI_Clk(spi_vif.o_SPI_Clk),
        .i_SPI_MISO(spi_vif.i_SPI_MISO),
        .o_SPI_MOSI(spi_vif.o_SPI_MOSI)
    );

    initial begin 
    spi_vif.i_Clk = 0;
    forever #5 spi_vif.i_Clk = ~spi_vif.i_Clk;
    end
  
  initial begin
    spi_vif.i_Rst_L  = 0;
    repeat(5) @(posedge spi_vif.i_Clk);
    spi_vif.i_Rst_L = 1;       // release reset
  end
    initial begin
      	int number_seq = 170;
        // put interface into config db — wildcard path means any component can get it
        uvm_config_db #(virtual spi_if)::set(null, "*", "vif", spi_vif);
      	uvm_config_db #(bit [1:0])::set(null,      "*", "spi_mode", spi_mode);
      	uvm_config_db #(int)::set(null,      "*", "number_seq", number_seq); 
        run_test("spi_test");   // kicks off UVM
    end
    initial begin
    $dumpfile("spi_master.vcd");
    $dumpvars(0, TB);
 end