#!/usr/bin/perl
use strict;

my $template = "attrChecker.html";
my $temp;
my $table;
my $missing;
# my $released;
my $miss;

$temp=`grep -ro '<Handler[ \t].*attributes="[^"]*"' /etc/shibboleth/shibboleth2.xml | grep -o 'attributes="[^"]*"' | cut -f2 -d'"'`;

chomp $temp;
my @arr = split / /, $temp;
foreach (@arr) {
  $table .= "<tr <shibmlpifnot ".$_."> class='warning text-danger'</shibmlpifnot>>\\n";
  $table .= "\\t<td>".$_."</td>\\n";
  $table .= "\\t<td><shibmlp ".$_." /></td>\\n";
  $table .= "</tr>\\n";

  $missing .= "<shibmlpifnot ".$_."> * ".$_."&#13;&#10;</shibmlpifnot>";
  
  $miss .= "<shibmlpifnot ".$_.">-".$_."<\\/shibmlpifnot>";
# $released .= "<shibmlpif ".$_."> * ".$_."</shibmlpif>\\n";
}

$temp = `sed -i -e 's/\\(.*miss=\\)[^\\"]*\\(\\".*\\)/\\1'"$miss"'\\2/' $template`;
$temp = `sed -i -e '/<!--TableStart-->/,/<!--TableEnd-->/c\\<!--TableStart-->\\n'"$table"'<!--TableEnd-->' $template`;
$temp = `sed -i -e '/The attributes that were not released to the service are:/,/^\$/c\\The attributes that were not released to the service are:\\n'"$missing" $template`;
#$temp = `sed -i -e '/Released as requested:/,/^\$/c\\Released as requested:\\n'"$released" $template`;

