<?php
/*
HHVMinfo - phpinfo page for HHVM HipHop Virtual Machine
Author: _ck_
License: WTFPL, free for any kind of use or modification,  I am not responsible for anything, please share your improvements
Version: 0.0.6

* revision history
0.0.6  2014-08-02  display fix for empty vs zero 
0.0.5  2014-07-31  try to determine config file from process command line (may not always work), style improvements
0.0.4  2014-07-30  calculate uptime from pid (may not work in all environments), fixed meta links
0.0.3  2014-07-29  display better interpretation of true, false, null and no value
0.0.2  2014-07-28  first public release

* known HHVM limitation as of 3.2
- cannot use eval, preg_replace/e, or create_function in RepoAuthoritative  mode
- cannot disable or reduce file stat frequency (without RepoAuthoritative mode)
- cannot custom format error log or use catch_workers_output
- cannot use phpinfo, php_ini_loaded_file, get_extension_funcs
- https://github.com/facebook/hhvm/labels/php5%20incompatibility

*/
?><!DOCTYPE html>
<html>
<head>
	<title>HHVMinfo</title>
	<meta name="ROBOTS" content="NOINDEX,NOFOLLOW,NOARCHIVE" />
<style type="text/css">
	body { background-color: #fff; color: #000; }
	body, td, th, h1, h2 { font-family: sans-serif; }
	pre { margin: 0px; font-family: monospace; }
	a:link,a:visited { color: #000099; text-decoration: none; }
	a:hover { text-decoration: underline; }
	table { border-collapse: collapse; border: 0; width: 934px; box-shadow: 1px 2px 3px #ccc; }
	.center { text-align: center; }
	.center table { margin: 1em auto; text-align: left; }
	.center th { text-align: center !important; }
	.middle { vertical-align:middle; }
	td, th { border: 1px solid #666; font-size: 75%; vertical-align: baseline; padding: 4px 5px; } 
	h1 { font-size: 150%; }
	h2 { font-size: 125%; }
	.p { text-align: left; }
	.e { background-color: #ccccff; font-weight: bold; color: #000; width:300px; }
	.h { background-color: #9999cc; font-weight: bold; color: #000; }
	.v { background-color: #ddd; max-width: 300px; overflow-x: auto; }
	.v i { color: #777; }
	.vr { background-color: #cccccc; text-align: right; color: #000; white-space: nowrap; }
	.b { font-weight:bold; }
	.white, .white a { color:#fff; } 	
	hr { width: 934px; background-color: #cccccc; border: 0px; height: 1px; color: #000; }
	.meta, .small { font-size: 75%; }
	.meta { margin: 2em 0; }
	.meta a, th a { padding: 10px; white-space:nowrap; }
	.buttons { margin:0 0 1em; }
	.buttons a { margin:0 15px; background-color: #9999cc; color:#fff; text-decoration:none; padding:1px; border:1px solid #000; display:inline-block; width:6em; text-align:center; box-shadow: 1px 2px 3px #ccc; }
	.buttons a.active { background-color: #8888bb; box-shadow:none; }
</style>
</head>

<body>
<div class="center">

<h1><a href="?">HHVMinfo</a></h1>

<div class="buttons">
        <a href="?INI&EXTENSIONS&FUNCTIONS&CONSTANTS&GLOBALS">ALL</a>
        <a <?php echo isset($_GET['INI'])?'class="active"':'' ?>" href="?INI">ini</a>
        <a <?php echo isset($_GET['EXTENSIONS'])?'class="active"':'' ?> href="?EXTENSIONS">Extensions</a>
        <a <?php echo isset($_GET['FUNCTIONS'])?'class="active"':'' ?> href="?FUNCTIONS">Functions</a>
        <a <?php echo isset($_GET['CONSTANTS'])?'class="active"':'' ?> href="?CONSTANTS">Constants</a>
        <a <?php echo isset($_GET['GLOBALS'])?'class="active"':'' ?> href="?GLOBALS">Globals</a>
</div>

<?php 

$globals=array_keys( $GLOBALS ); 

if ( empty($_GET)  || count($_GET)>4 || isset($_GET['SUMMARY']) ) {
	if ( ($pidfile=ini_get('pid')) || ($pidfile=ini_get('hhvm.pid_file')) ) {
		$uptime=($pidfile)&&($mtime=@filemtime($pidfile))?(new DateTime('@'.$mtime))->diff(new DateTime('NOW'))->format('%a days, %h hours, %i minutes'):'<i>unknown<i>';
		if ( !($inifile=(function_exists('php_ini_loaded_file')?php_ini_loaded_file():'')) && ($pid=@file_get_contents($pidfile)) 
			&& ($cmdline=@file_get_contents("/proc/$pid/cmdline")) ) { $inifile=preg_match('@-?-c(onfig)?\s*([^ ]+?)($|\s|--)@',$cmdline,$match)?$match[2]:''; }
	} else { $uptime=$inifile='<i>unknown</i>'; }
	print_table( array(
		'Host'=>function_exists('gethostname')?@gethostname():@php_uname('n'),
		'System'=>php_uname(),
		'PHP Version'=>phpversion(),
		'HHVM Version'=>ini_get('hphp.compiler_version'),
		'HHVM compiler id'=>ini_get('hphp.compiler_id'),
		'SAPI'=>php_sapi_name().' '.ini_get('hhvm.server.type'),
		'Loaded Configuration File'=>$inifile,
		'Uptime'=>$uptime,
	));
}

if ( isset($_GET['INI']) && $ini=ini_get_all() ) { 
  	ksort($ini); echo '<h2 id="ini">ini</h2>'; print_table($ini,array('Directive','Local Value','Master Value','Access'),false); 
  	echo '<h2>access level legend</h2>';
  	print_table(array('Entry can be set in user scripts, ini_set()'=>INI_USER,'Entry can be set in php.ini, .htaccess, httpd.conf'=>INI_PERDIR,
     			'Entry can be set in php.ini or httpd.conf'=>INI_SYSTEM,'<div style="width:865px">Entry can be set anywhere</div>'=>INI_ALL ));
}

if ( isset($_GET['EXTENSIONS']) && $extensions=get_loaded_extensions(true) ) { 
	echo '<h2 id="extensions">extensions</h2>'; natcasesort( $extensions); print_table($extensions,false,true); 
}

if ( isset($_GET['FUNCTIONS']) && $functions=get_defined_functions() ) { 
	 echo '<h2 id="functions">functions</h2>'; natcasesort( $functions['internal']); print_table($functions['internal'],false,true); 
}

if ( isset($_GET['CONSTANTS']) && $constants=get_defined_constants(true) ) { 
	ksort( $constants); foreach ( $constants as $key=>$value) { if (!empty($value)) { ksort( $value); echo '<h2 id="constants-',$key,'">Constants (',$key,')</h2>'; print_table($value); } } 
}

if ( isset($_GET['GLOBALS']) ) { 
	if (0) { $_SERVER; $_ENV; $_SESSION; $_COOKIE; $_GET; $_POST; $_REQUEST; $_FILES; }	// PHP 5.4+ JIT
	$order=array_flip(array('_SERVER','_ENV','_COOKIE','_GET','_POST','_REQUEST','_FILES'));
	foreach ( $order as $key=>$ignore ) { if ( isset($GLOBALS[$key]) ) { echo '<h2 id="',$key,'">$',$key,'</h2>';  if ( empty($GLOBALS[$key]) ) { echo '<hr>'; } else { print_table( $GLOBALS[$key]); } } }
	natcasesort($globals); $globals=array_flip($globals); unset( $globals['GLOBALS'] );  
	foreach ( $globals as $key=>$ignore ) { if ( !isset($order[$key]) ) { echo '<h2 id="',$key,'">$',$key,'</h2>';  if ( empty($GLOBALS[$key]) ) { echo '<hr>'; } else { print_table( $GLOBALS[$key]); } } }
}

?>

<div class="meta">
	<a href="http://hhvm.com/blog">HHVM blog</a> | 
	<a href="https://github.com/facebook/hhvm/wiki">HHVM wiki</a> | 
	<a href="https://github.com/facebook/hhvm/blob/master/hphp/NEWS">HHVM changelog</a> | 		
	<a href="https://github.com/facebook/hhvm/commits/master">HHVM commits</a> | 
	<a href="http://webchat.freenode.net/?channels=hhvm">#HHVM irc chat</a> | 
	<a href="https://gist.github.com/ck-on/67ca91f0310a695ceb65?hhvminfo.php">HHVMinfo latest</a>
</div>

</div></body></html>

<?php

function print_table( $array, $headers=false, $formatkeys=false, $formatnumeric=false ) { 
	if ( empty($array) || !is_array($array) ) { return; } 
  	echo '<table border="0" cellpadding="3">';
  	if ( !empty($headers) ) { 
  		if ( !is_array( $headers) ) { $headers=array_keys( reset( $array) ); }
  		echo '<tr class="h">'; foreach ( $headers as $value) { echo '<th>',$value,'</th>'; } echo '</tr>';  			
  	}
  	foreach ( $array as $key=>$value ) { 
    		echo '<tr>';
    		if ( !is_numeric( $key) || !$formatkeys ) { echo '<td class="e">',($formatkeys?ucwords(str_replace('_',' ',$key)):$key),'</td>'; }
    		if ( is_array($value) ) { foreach ($value as $column) { echo '<td class="v">',format_special($column,$formatnumeric),'</td>'; } }
    		else { echo '<td class="v">',format_special($value,$formatnumeric),'</td>'; } 
    		echo '</tr>';
	}
 	echo '</table>';
}

function format_special( $value, $formatnumeric ) { 
	if ( is_array($value) ) { $value='<i>array</i>'; }
	elseif ( is_object($value) ) { $value='<i>object</i>'; }
    	elseif ( $value===true ) { $value='<i>true</i>'; }
    	elseif ( $value===false ) { $value='<i>false</i>'; }
    	elseif ( $value===NULL ) { $value='<i>null</i>'; }
    	elseif ( $value===0 || $value===0.0 || $value==='0' ) { $value='0'; }    	
    	elseif ( empty($value) ) { $value='<i>no value</i>'; }
	elseif ( is_string($value) && strlen($value)>50 ) { $value=implode('&#8203;',str_split($value,45)); }
	elseif ( $formatnumeric && is_numeric($value) ) { 
        			if ( $value>1048576 ) { $value=round($value/1048576,1).'M'; }
        			elseif ( is_float($value) ) { $value=round($value,1); }
      	}
	return $value;
}