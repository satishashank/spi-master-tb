interface spi_if;
    logic i_Clk;       // FPGA Clock
    logic i_Rst_L;     // FPGA Reset
    logic [7:0] i_TX_Byte;
    logic i_TX_DV;
    logic o_TX_Ready;
    logic o_RX_DV;
    logic [7:0] o_RX_Byte;
    logic o_SPI_Clk;
    logic i_SPI_MISO;
    logic o_SPI_MOSI;
endinterface
