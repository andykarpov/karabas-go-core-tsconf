<?php

$filename = 'icons4.pf';
$size = filesize($filename);
$f = fopen($filename, 'rb');
$contents = fread($f, $size);
fclose($f);

$o = fopen('icons.coe', 'w');

fwrite($o, "memory_initialization_radix = 16;\n");
fwrite($o, "memory_initialization_vector = \n");

$a = 0;
for ($j=0; $j<256; $j++) {
	for ($i=0; $i<8; $i++) {
		fwrite($o,  (((ord($contents[$j]) >> (7-$i)) & 1) ? '01': '00') . (($a < 256*8-1) ? ",\n" : ";\n"));
		$a++;
	}
}

fclose($o);
