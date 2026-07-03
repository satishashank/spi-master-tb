

class spi_item extends uvm_sequence_item;
    rand bit [7:0] data;

    `uvm_object_utils_begin(spi_item) //object registration macro
        `uvm_field_int(data, UVM_DEFAULT) //field registration macro uvm_default generate all the functions
    `uvm_object_utils_end
    constraint data_dist {
        data dist {0:/5, 8'hFF:/5, 8'h55:/5, 8'hAA:/5, [1:8'hFE]:/85};
    }

    function new(string name = "spi_item");
        super.new(name);
    endfunction
  
endclass
// declare two imp types at package scope — outside the class
// this creates two different write() implementations
`uvm_analysis_imp_decl(_mosi)   // creates uvm_analysis_imp_mosi
`uvm_analysis_imp_decl(_miso)   // creates uvm_analysis_imp_miso

class spi_coverage extends uvm_component;
    `uvm_component_utils(spi_coverage)

    // two exports — one per path
    uvm_analysis_imp_mosi #(spi_item, spi_coverage) ap_mosi;
    uvm_analysis_imp_miso #(spi_item, spi_coverage) ap_miso;

    spi_item mosi_item;
    spi_item miso_item;
    bit [1:0] spi_mode;

    covergroup mosi_cg;
    cp_data: coverpoint mosi_item.data {
        bins zero     = {8'h00};
        bins lsb_only = {8'h01};
        bins alt_01   = {8'h55};
        bins msb_only = {8'h80};
        bins alt_10   = {8'hAA};
        bins all_ones = {8'hFF};

        // everything else split into 16 buckets
        bins rest[16] = default;
    }
endgroup

    covergroup miso_cg;
        cp_data: coverpoint miso_item.data {
            bins zero     = {8'h00};
        bins lsb_only = {8'h01};
        bins alt_01   = {8'h55};
        bins msb_only = {8'h80};
        bins alt_10   = {8'hAA};
        bins all_ones = {8'hFF};

        // everything else split into 16 buckets
        bins rest[16] = default;
    }
endgroup

    covergroup mode_cg;
        cp_mode: coverpoint spi_mode {
            bins mode0 = {2'b00};
            bins mode1 = {2'b01};
            bins mode2 = {2'b10};
            bins mode3 = {2'b11};
        }
    endgroup

    function new(string name = "spi_coverage", uvm_component parent = null);
        super.new(name, parent);
        mosi_cg = new();
        miso_cg = new();
        mode_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap_mosi = new("ap_mosi", this);
        ap_miso = new("ap_miso", this);
        if(!uvm_config_db #(bit [1:0])::get(this, "", "spi_mode", spi_mode))
            `uvm_fatal("CFG", "spi_coverage: no spi_mode found")
        mode_cg.sample();  // sample once — mode never changes
    endfunction

    // called when monitor's ap_tx_master broadcasts
    function void write_mosi(spi_item t);
        this.mosi_item = t;
        mosi_cg.sample();
        `uvm_info("COV:MOSI", $sformatf("sampled %0h", t.data), UVM_HIGH)
    endfunction

    // called when monitor's ap_rx_master broadcasts
    function void write_miso(spi_item t);
        this.miso_item = t;
        miso_cg.sample();
        `uvm_info("COV:MISO", $sformatf("sampled %0h", t.data), UVM_HIGH)
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf(
            "MOSI: %0.2f%%  MISO: %0.2f%%  Mode: %0.2f%%",
            mosi_cg.get_coverage(),
            miso_cg.get_coverage(),
            mode_cg.get_coverage()), UVM_NONE)
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
    function new(string name = "spi_driver_slave", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual spi_if)::get(this, "", "vif", spi_vif))
            `uvm_fatal("CFG", "spi_driver_slave: no vif found")
        if(!uvm_config_db #(bit [1:0])::get(this, "", "spi_mode", spi_mode))
            `uvm_fatal("CFG", "spi_driver_slave: no spi_mode found")
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

class spi_monitor_master extends uvm_monitor;

    virtual spi_if spi_vif;
    bit [1:0] spi_mode;

    uvm_analysis_port #(spi_item) ap_tx_master;  // i_TX_Byte  — what entered DUT
    uvm_analysis_port #(spi_item) ap_rx_master;  // o_RX_Byte  — what DUT shifted in


    `uvm_component_utils(spi_monitor_master) //component registration macro
    function new(string name = "spi_monitor_master", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual spi_if)::get(this, "", "vif", spi_vif))
            `uvm_fatal("CFG", "spi_monitor: no vif found")
        if(!uvm_config_db #(bit [1:0])::get(this, "", "spi_mode", spi_mode))
            `uvm_fatal("CFG", "spi_monitor: no spi_mode found")
        ap_tx_master = new("ap_tx_master", this);
        ap_rx_master = new("ap_rx_master", this);
    endfunction

    task mon_data_rx_master();
    forever begin
        spi_item rx;
        rx = spi_item::type_id::create("rx");
        @(posedge spi_vif.i_Clk iff spi_vif.o_RX_DV);
        rx.data = spi_vif.o_RX_Byte;
        `uvm_info("MON:Master", $sformatf("Received data from slave, with mode %0h: %0h", spi_mode, rx.data), UVM_NONE);
        ap_rx_master.write(rx);
    end
    endtask
    task mon_data_tx_master();
    forever begin
        spi_item tx;
        tx = spi_item::type_id::create("tx");
        @(posedge spi_vif.i_Clk iff spi_vif.i_TX_DV);
        tx.data = spi_vif.i_TX_Byte;
        `uvm_info("MON:Master", $sformatf("Sent data to slave, with mode %0h: %0h", spi_mode, tx.data), UVM_NONE);
        ap_tx_master.write(tx);
    end
    endtask

    task run_phase(uvm_phase phase);
    fork
        this.mon_data_rx_master();
        this.mon_data_tx_master();
    join_none
    endtask
endclass //spi_monitor extends uvm_monitor


class spi_monitor_slave extends uvm_monitor;

    virtual spi_if spi_vif;
    bit [1:0] spi_mode;

    uvm_analysis_port #(spi_item) ap_rx_slave;   // o_SPI_MOSI — what DUT shifted out
    uvm_analysis_port #(spi_item) ap_tx_slave;

    `uvm_component_utils(spi_monitor_slave) //component registration macro
    function new(string name = "spi_monitor_slave", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual spi_if)::get(this, "", "vif", spi_vif))
            `uvm_fatal("CFG", "spi_monitor: no vif found")
        if(!uvm_config_db #(bit [1:0])::get(this, "", "spi_mode", spi_mode))
            `uvm_fatal("CFG", "spi_monitor: no spi_mode found")
        ap_rx_slave  = new("ap_rx_slave",  this);
        ap_tx_slave  = new("ap_tx_slave",  this);
    endfunction

    task mon_data_rx_slave();
    forever begin
        int i;
        spi_item rx;
        rx = spi_item::type_id::create("rx");

        @(negedge spi_vif.o_TX_Ready);
        for(i = 0; i < 8; i++) begin
            if(spi_mode[1] == spi_mode[0])
            @(posedge spi_vif.o_SPI_Clk);
            else
            @(negedge spi_vif.o_SPI_Clk);
            rx.data[7-i] = spi_vif.o_SPI_MOSI;
        end
        `uvm_info("MON:Slave", $sformatf("Received data from master, with mode %0h: %0h", spi_mode, rx.data), UVM_NONE);
        ap_rx_slave.write(rx);
    end
    endtask

    task mon_data_tx_slave();
        forever begin
            int i;
            spi_item tx;
            tx = spi_item::type_id::create("tx");
            @(negedge spi_vif.o_TX_Ready);
            for(i = 0; i < 8; i++) begin
                if(spi_mode[0] == spi_mode[1]) 
                    @(posedge spi_vif.o_SPI_Clk);
                else 
                    @(negedge spi_vif.o_SPI_Clk);
                    tx.data[7-i] = spi_vif.i_SPI_MISO;
                end
            `uvm_info("MON:Slave", $sformatf("Sent data to master, with mode %0h: %0h", spi_mode, tx.data), UVM_NONE);
            ap_tx_slave.write(tx);
        end
    endtask

    task run_phase(uvm_phase phase);
    fork
        this.mon_data_rx_slave();
      	this.mon_data_tx_slave();
    join_none
    endtask
endclass //spi_monitor_slave extends uvm_monitor

class spi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(spi_scoreboard)

    // FIFOs receive from monitor analysis ports
    uvm_tlm_analysis_fifo #(spi_item) fifo_tx_master; // what entered DUT
    uvm_tlm_analysis_fifo #(spi_item) fifo_rx_slave;  // what DUT shifted out
    uvm_tlm_analysis_fifo #(spi_item) fifo_tx_slave;  // what slave sent in
    uvm_tlm_analysis_fifo #(spi_item) fifo_rx_master; // what DUT reconstructed

    int pass_mosi, fail_mosi;
    int pass_miso, fail_miso;

    function new(string name = "spi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        fifo_tx_master = new("fifo_tx_master", this);
        fifo_rx_slave  = new("fifo_rx_slave",  this);
        fifo_tx_slave  = new("fifo_tx_slave",  this);
        fifo_rx_master = new("fifo_rx_master", this);
    endfunction

    task run_phase(uvm_phase phase);
        fork
            // MOSI check: what went in vs what came out serially
            forever begin
                spi_item tx_m, rx_s;
                fifo_tx_master.get(tx_m);  // what driver put on i_TX_Byte
                fifo_rx_slave.get(rx_s);   // what DUT shifted on o_SPI_MOSI
                if(tx_m.data !== rx_s.data) begin
                    `uvm_error("SCB:MOSI", $sformatf(
                        "MISMATCH exp=%0h got=%0h", tx_m.data, rx_s.data))
                    fail_mosi++;
                end else begin
                    `uvm_info("SCB:MOSI", $sformatf(
                        "PASS %0h", tx_m.data), UVM_MEDIUM)
                    pass_mosi++;
                end
            end
            // MISO check: what slave put on wire vs what DUT reconstructed
            forever begin
                spi_item tx_s, rx_m;
                fifo_tx_slave.get(tx_s);   // what slave drove on i_SPI_MISO
                fifo_rx_master.get(rx_m);  // what DUT put on o_RX_Byte
                if(tx_s.data !== rx_m.data) begin
                    `uvm_error("SCB:MISO", $sformatf(
                        "MISMATCH exp=%0h got=%0h", tx_s.data, rx_m.data))
                    fail_miso++;
                end else begin
                    `uvm_info("SCB:MISO", $sformatf(
                        "PASS %0h", tx_s.data), UVM_MEDIUM)
                    pass_miso++;
                end
            end
        join_none
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf(
            "MOSI: PASS=%0d FAIL=%0d | MISO: PASS=%0d FAIL=%0d",
            pass_mosi, fail_mosi, pass_miso, fail_miso), UVM_NONE)
    endfunction
endclass

class spi_agent_master extends uvm_agent;
    `uvm_component_utils(spi_agent_master) //component registration macro

    spi_driver_master driver;
    spi_monitor_master monitor;

    uvm_sequencer #(spi_item) spi_seqr_m;

    function new(string name = "spi_agent_master", uvm_component parent = null);
        super.new(name, parent);        
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      	driver = spi_driver_master::type_id::create("driver", this);
        monitor = spi_monitor_master::type_id::create("monitor", this);
        spi_seqr_m = uvm_sequencer #(spi_item)::type_id::create("spi_seqr_m",this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(spi_seqr_m.seq_item_export);
    endfunction

endclass //spi_agent_master extends uvm_agent

class spi_agent_slave extends uvm_agent;
    `uvm_component_utils(spi_agent_slave) //component registration macro

    spi_driver_slave driver;
    spi_monitor_slave monitor;

    uvm_sequencer #(spi_item) spi_seqr_s;

    function new(string name = "spi_agent_slave", uvm_component parent = null);
        super.new(name, parent);        
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      	driver = spi_driver_slave::type_id::create("driver", this);
        monitor = spi_monitor_slave::type_id::create("monitor", this);
        spi_seqr_s = uvm_sequencer #(spi_item)::type_id::create("spi_seqr_s",this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(spi_seqr_s.seq_item_export);
    endfunction
endclass //spi_agent_slave extends uvm_agent


class spi_env extends uvm_env;
    `uvm_component_utils(spi_env) //component registration macro

    spi_agent_master master_agent;
    spi_agent_slave slave_agent;
    spi_scoreboard scoreboard;
    spi_coverage coverage;

    function new(string name = "spi_env", uvm_component parent = null);
        super.new(name, parent);        
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      	master_agent = spi_agent_master::type_id::create("master_agent", this);
      	slave_agent = spi_agent_slave::type_id::create("slave_agent", this);
        scoreboard = spi_scoreboard::type_id::create("scoreboard", this);
        coverage = spi_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        master_agent.monitor.ap_tx_master.connect(scoreboard.fifo_tx_master.analysis_export);
        master_agent.monitor.ap_rx_master.connect(scoreboard.fifo_rx_master.analysis_export);
        slave_agent.monitor.ap_tx_slave.connect(scoreboard.fifo_tx_slave.analysis_export);
        slave_agent.monitor.ap_rx_slave.connect(scoreboard.fifo_rx_slave.analysis_export);
        master_agent.monitor.ap_tx_master.connect(coverage.ap_mosi);
        slave_agent.monitor.ap_tx_slave.connect(coverage.ap_miso);
    endfunction

endclass


class spi_test extends uvm_test;
    `uvm_component_utils(spi_test) //component registration macro
  	int number_seq;

    spi_env env;

    function new(string name = "spi_test", uvm_component parent = null);
        super.new(name, parent);        
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      	env = spi_env::type_id::create("env", this);
        if(!uvm_config_db #(int)::get(this, "", "number_seq", number_seq))
            `uvm_warning("CFG", "spi_test: no number_seq found, using default 10")
        // No fatal — better to have default
    endfunction

    task run_phase(uvm_phase phase);
        spi_sequence seq_m;
        spi_sequence seq_s;
        phase.raise_objection(this);
        `uvm_info("[Test]", "Starting SPI Test", UVM_MEDIUM)
        
        seq_m = spi_sequence::type_id::create("seq_m");
        seq_s = spi_sequence::type_id::create("seq_s");

        seq_m.n= this.number_seq;
        seq_s.n= this.number_seq;

        fork
            seq_m.start(env.master_agent.spi_seqr_m);
            seq_s.start(env.slave_agent.spi_seqr_s);
        join
      	#500;  // give last transaction time to complete through DUT
        phase.drop_objection(this);
        
    endtask
endclass //spi_test extends uvm_test