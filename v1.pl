#!/usr/bin/perl 

use strict;

use DBI;
use DBD::Pg;

my $DEBUG_MODE = 1;

my $CFGFile = 'sql_types.conf';
my @cfgTypes;


my $MySQL_HOST		= "192.168.0.1";
my $MySQL_PORT		= "3306";
my $MySQL_DB		= "SRC_DB";
my $MySQL_USER		= "user";
my $MySQL_PASS		= "123321";

my $PgSQL_HOST		= "$MySQL_HOST";
my $PgSQL_PORT		= "5432";
my $PgSQL_DB		= "my2pg";
my $PgSQL_USER		= "DST_DB";
my $PgSQL_PASS		= "123321";

my $PgSQL_DST_SCHEMA	= "001";

my $dsn_pgsql		= "DBI:Pg:database=$PgSQL_DB;host=$PgSQL_HOST;port=$PgSQL_PORT";
my $dsn_mysql		= "DBI:mysql:database=$MySQL_DB;host=$MySQL_HOST;port=$MySQL_PORT";

my $dump_header		= "";
my $dump_create_types	= "";
my $dump_create_tables	= "";
my $dump_create_rights	= "";
my $dump_create_indexes	= "";
my $dump_alter_rights	= "";

my $JOB_PROTOCOL	= "";

####################################################################################################################################
#
# Conversion types definition
#
####################################################################################################################################
my @field_type = (
    ["tinyint","smallint","nosize"],
    ["smallint","smallint","nosize"],
    ["mediumint","integer","nosize"],
    ["int","integer","nosize"],
    ["bigint","bigint","nosize"],
    ["tinyint unsigned","smallint","nosize"],
    ["smallint unsigned","smallint","nosize"],
    ["mediumint unsigned","integer","nosize"],
    ["int unsigned","bigint","nosize"],
    ["bigint unsigned","numeric(20,0)","nosize"],
    ["decimal","decimal",""],
    ["numeric","numeric",""],
    ["float","float","nosize"],
    ["float unsigned","float","nosize"],
    ["double","double precision","nosize"],
    ["bit","bit",""],
    ["boolean","boolean","nosize"],
    ["date","date","nosize"],
    ["datetime","timestamp","nosize"],
    ["timestamp","timestamp","nosize"],
    ["time","varchar(9)","nosize"],
    ["year","numeric(4,0)","nosize"],
    ["tinytext","text","nosize"],
    ["mediumtext","text","nosize"],
    ["longtext","text","nosize"],
    ["text","text","nosize"],
    ["char","char",""],
    ["varchar","varchar",""],
    ["binary","bytea","nosize"],
    ["varbinary","bytea","nosize"],
    ["tinyblob","bytea","nosize"],
    ["mediumblob","bytea","nosize"],
    ["longblob","bytea","nosize"],
    ["blob","bytea","nosize"],
    ["enum","check",""],
    ["set","varchar",""]
);

# not used for a while
my @sql_extras = (
    ["auto_incremant","serial",""],
    ["timestamp_on_update","tr_update_","f_update_timestamp"]
);


print scalar(@field_type) . "types found\n";

my $dbh_mysql = DBI-> connect($dsn_mysql, $MySQL_USER, $MySQL_PASS, { RaiseError => 1, AutoCommit => 0 } );
my $dbh_pgsql = DBI-> connect($dsn_pgsql, $PgSQL_USER, $PgSQL_PASS, { RaiseError => 1, AutoCommit => 0 } );

$dbh_mysql->do("set names 'utf8'");

##
#
# Prepare variables
#
##

if($PgSQL_DST_SCHEMA ne ""){
    $dump_header = "set search_path = \"$PgSQL_DST_SCHEMA\"\, pg_catalog\;\n";
}

my $qGetMySQLTables	= "show tables";
my $qGetMySQLStructure	= "describe ";


### Let's go

my $sth_mysql = $dbh_mysql->prepare($qGetMySQLTables);

$sth_mysql->execute();

while (my @row = $sth_mysql->fetchrow_array){
    my $sth_mysql01 = $dbh_mysql->prepare("$qGetMySQLStructure.@row");
    $sth_mysql01->execute();
    
    $dump_create_tables = $dump_create_tables."create table @row[0](\n";
    my $table_struct = $sth_mysql01->fetchall_arrayref;
    my $row_t;
    my $pos = 0;
    foreach $row_t(@$table_struct){
	my $i = "";
	my $tmpstr = "";

	# store field name
	my $strConverted = "\t@$row_t[0]";

	$pos++;
	
        # Search the type in array to transform
        foreach $i(@field_type){
            $tmpstr = @$row_t[1];
	    # clear brackets and values inside
	    $tmpstr =~ s/\((.*?)\)//g;

            if($tmpstr eq @$i[0]){
		# check for the extra parameters
		if(@$row_t[5] ne ""){
		    # if we got extra params
		    if("\L@$row_t[5]" eq "auto_increment"){
			# creating autoincrement using serial type
		        $strConverted = "$strConverted serial";
		    } else {
			if(@$i[1] eq "timestamp"){
			    # sorry, ignoring "on update" event in extras for a while. later trigger be here. promise ;)
			    $strConverted = "$strConverted timestamp";
			    if("\L@$row_t[2]" eq "no"){ "$strConverted not null" }
			    if("\L@$row_t[4]" eq "current_timestamp"){ $strConverted = "$strConverted default @$row_t[4]" }
			    } else {
				$JOB_PROTOCOL = "$JOB_PROTOCOL\nStrange default value for @row[0].@$row_t[0].@$i[1] default @$row_t[2]";
			    }
		    }
		} else {
		    # No extras fields
		    # check for the complex types
		    if("\L@$i[1]" eq "check"){

			# convert enum type as check constraint
			$strConverted = "$strConverted varchar ";
		
			if("\L@$row_t[2]" eq "no"){ $strConverted = "$strConverted not null" }
			if(@$row_t[4] ne ""){ $strConverted = "$strConverted default '@$row_t[4]'" }
		
			@$row_t[1] =~ /(\(.*?\))/;
			$strConverted = "$strConverted check(@$row_t[0] in$1)\,";
		
		    } elsif("\L@$i[1]" eq "type") {
			# convert mysql enum field as pgsql type enum
		    } else {
			# Simple type conversion
			$strConverted = "$strConverted @$i[1]";
		    
			if("\L@$i[2]" ne "nosize"){
			    # type with size
			    @$row_t[1] =~ /(\(.*?\))/;
			    $strConverted = "$strConverted$1";
			}
			if("\L@$row_t[2]" eq "no"){ $strConverted = "$strConverted not null" }
			if(length(@$row_t[4]) > 0){ $strConverted = "$strConverted default '@$row_t[4]'" }
		    }
		}
		
		
	    }
	}
	if(scalar(@$table_struct != $pos)) {
	    $strConverted = "$strConverted\,"; 
	}
	$strConverted = "$strConverted\t-- " . @$row_t[0] . " " . @$row_t[1] . " " . @$row_t[2] . " " . @$row_t[3] . "" . @$row_t[4] . "" . @$row_t[5] . "\n";
	$dump_create_tables = "$dump_create_tables$strConverted";
    }
    $dump_create_tables = "$dump_create_tables\)\;\n\n\n\n";
}

print $dump_header;
print $dump_create_tables;

# printing protocol
print "$JOB_PROTOCOL";

&ReadCFG();
&getType();


$dbh_mysql->disconnect;
$dbh_pgsql->disconnect;

sub ConvertType(){
# Type conversion is hardcoded yet. But in future it must be replaced by config file sql_types.conf
    my($str) = @ARGV;
}

sub getType(){
# service function for getting type conversion information

}

sub CheckDefaultValue(){
}


sub CreateDBDump() {
}
sub ReadCFG(){

    my $line = "";
    my $rec = {};

    open(F, $CFGFile) || die "Couldn't open $CFGFile: $!";

    while($line = <F>){
        chomp($line);

        ($rec->{SRC}, $rec->{DST}, $rec->{FLAG}) = split (/\;/, $line);

	#print $rec->{SRC}.">".$rec->{DST}.">".$rec->{FLAG}."\n";
	#print $dTypes[0]{SRC}.">".$dTypes[0]{DST}.">".$dTypes[0]{FLAG}."\n";
        push @cfgTypes, $rec;
        $rec={};
    }

    close(F);

}



