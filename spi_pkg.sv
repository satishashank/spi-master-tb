class spi_item extends uvm_sequence_item;
    randc bit [7:0] data;

    `uvm_object_utils_begin(spi_item) //object registration macro
        `uvm_field_int(data, UVM_DEFAULT) //field registration macro uvm_default generate all the functions
    `uvm_object_utils_end

    function new(string name = "spi_item");
        super.new(name);
    endfunction
endclass

class spi_sequence extends uvm_sequence #(spi_item);
  int n;
    `uvm_object_utils(spi_sequence) //object registration macro

    function new(string name = "spi_sequence");
        super.new(name);
    endfunction
    task body();
    repeat(n) begin
        spi_item item;
        item = spi_item::type_id::create("item");
        start_item(item);
        assert(item.randomize());
        finish_item(item);
    end
    endtask
endclass

class spi_driver_master extends uvm_driver #(spi_item);

    virtual spi_if spi_vif;

    `uvm_component_utils(spi_driver_master) //component registration macro
    function new(string name = "spi_driver_master", uvm_component parent = null);
        super.new(name, parent);        
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual spi_if)::get(this, "", "vif", spi_vif))
            `uvm_fatal("CFG", "spi_driver_master: no vif found")
    endfunction
    
    task run_phase(uvm_phase phase);
        spi_item item;
        forever begin
            seq_item_port.get_next_item(item);
            @(posedge spi_vif.i_Clk iff spi_vif.o_TX_Ready);
            spi_vif.i_TX_DV <= 1;
            spi_vif.i_TX_Byte <= item.data;
            @(posedge spi_vif.i_Clk);
            spi_vif.i_TX_DV <= 0;
            seq_item_port.item_done();
        end
    endtask
endclass //spi_driver_master extends uvm_driver

class spi_driver_slave extends uvm_driver #(spi_item);

    virtual spi_if spi_vif;
    bit [1:0] spi_mode;


    `uvm_component_utils(spi_driver_slave) //component registration macro
    function new(string name = "spi_driver_slave", uvm_component parent = null, bit [1:0] spi_mode = 2'b00);
        super.new(name, parent);
        this.spi_mode = spi_mode;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual spi_if)::get(this, "", "vif", spi_vif))
            `uvm_fatal("CFG", "spi_driver_slave: no vif found")
    endfunction
    
    task run_phase(uvm_phase phase);
        int i;
        spi_item item;
        forever begin
            seq_item_port.get_next_item(item);
            @(negedge spi_vif.o_TX_Ready);
            if(spi_mode[0] == 0) begin
                spi_vif.i_SPI_MISO<= item.data[7];

                for(i = 1; i < 8; i++) begin
                    if(spi_mode[1] == 0) begin
                        @(negedge spi_vif.o_SPI_Clk);
                    end
                    else begin
                        @(posedge spi_vif.o_SPI_Clk);
                    end
                    spi_vif.i_SPI_MISO <= item.data[7-i];
                end
            end
            else begin
                for(i = 0; i < 8; i++) begin
                    if(spi_mode[1] == 0) begin
                        @(posedge spi_vif.o_SPI_Clk);
                    end
                    else begin
                        @(negedge spi_vif.o_SPI_Clk);
                    end
                    spi_vif.i_SPI_MISO <= item.data[7-i];
                end
            end
            seq_item_port.item_done();
        end
    endtask
endclass //spi_driver_slave extends uvm_driver

class spi_test extends uvm_test;
    `uvm_component_utils(spi_test) //component registration macro

    spi_driver_master master_driver;
    spi_driver_slave slave_driver;

    uvm_sequencer #(spi_item) spi_seqr_m;
    uvm_sequencer #(spi_item) spi_seqr_s;

    function new(string name = "spi_test", uvm_component parent = null);
        super.new(name, parent);        
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      	master_driver = spi_driver_master::type_id::create("master_driver", this);
      	slave_driver = spi_driver_slave::type_id::create("slave_driver", this);
        spi_seqr_m = uvm_sequencer #(spi_item)::type_id::create("spi_seqr_m",this);
        spi_seqr_s = uvm_sequencer #(spi_item)::type_id::create("spi_seqr_s",this);

    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
      master_driver.seq_item_port.connect(spi_seqr_m.seq_item_export);
      slave_driver.seq_item_port.connect(spi_seqr_s.seq_item_export);
    endfunction

    task run_phase(uvm_phase phase);
        spi_sequence seq_m;
        spi_sequence seq_s;
        phase.raise_objection(this);
        `uvm_info("[Test]", "Starting SPI Test", UVM_MEDIUM)
        
        seq_m = spi_sequence::type_id::create("seq_m");
        seq_s = spi_sequence::type_id::create("seq_s");

        seq_m.n=10;
        seq_s.n=10;

        fork
            seq_m.start(spi_seqr_m);
            seq_s.start(spi_seqr_s);
        join
      	#500;  // give last transaction time to complete through DUT
        phase.drop_objection(this);
        
    endtask
endclass //spi_test extends uvm_test
