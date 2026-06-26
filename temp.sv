/*Assume generator class consists of three 8-bit data members (x,y, and z). Write a code to generate 20 random values for all the data members at an interval of 20 ns.*/
class generator;
    rand bit[7:0] x;
    rand bit[7:0] y;
    rand bit[7:0] z;
    function void display();
        $display("x: %0h, y: %0h, z: %0h", x, y, z);
    endfunction
endclass
module TB;
    generator gen;
    int i;
    initial begin
        gen = new();
        for(i = 0;i<20;i++) begin
            #20;
            gen.randomize();
            gen.display();
        end
    end
endmodule