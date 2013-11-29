#!/usr/bin/perl -w

use strict;

use Curses;
use Curses::UI;
use Device::SerialPort;
use Getopt::Std;

require 'LICENSE';


sub update_info;
sub update_info_monitor;
sub getparam;
sub send_command;
sub read_response;
sub filter_command_list;
sub send_button;
sub help_button;
sub log_start;
sub serial_port_setup;
sub show_page;
sub save_notes_dialog;
sub quit_dialog;
sub about_dialog;
sub license_dialog;
sub _;
sub HELP_MESSAGE;
sub VERSION_MESSAGE;
sub LICENSE_MESSAGE;


# set defaults
my %opts = (
	d => '/dev/cuaU0',
	l => undef,
	c => 0,
	r => 0
);
Getopt::Std::getopts('d:l:i:crhvs', \%opts);

my $intl_file = undef;
if (defined($opts{i})) {
	$intl_file = $opts{i};
}

if (defined($opts{h})) {
	HELP_MESSAGE();
}
if (defined($opts{v})) {
	VERSION_MESSAGE();
}

my $bsd_license = do 'LICENSE';
if (defined($opts{s})) {
	LICENSE_MESSAGE();
}


my $retval = 0;
my $filter = '';
my $logging = 0;

my %param = ();
my %param_label = ();

my $PortObj = undef;
my $serial_device = undef;
$serial_device = $opts{d};
my $written = undef;
my $line_monitor = undef;
my $monitoring = 'CGETDATA';


my $cui = new Curses::UI(
	-color_support => $opts{r},
	-compat => $opts{c},
	-width => 80
);


########## Main window ##########
my $win_main = $cui->add(
	'win_main', 'Window',
	-border => 1,
	-title => 'E85 Power'
);

# menu
my $menu = $cui->add(
	'menu','Menubar',
	-menu =>	[
			{
			-label => 'E85 Power',
			-submenu =>	[
					{
					-label => _('Reconnect'),
					-value => sub {
						if (defined($opts{l})) {
							$cui->status( -message => _('Currently in log file mode') ); sleep 1; $cui->nostatus();
						} else {
							serial_port_setup();
						}
					}
					},
					{ -label => '', -value => sub {} },
					{ -label => _('Quit') . "    ^Q", -value => \&quit_dialog }
					]
			},
			{
			-label => 'Page',
			-submenu =>	[
					{ -label => _('Status'), -value => sub { show_page(0); } },
					{ -label => _('Details'), -value => sub { show_page(1); } },
					{ -label => _('Control'), -value => sub { show_page(2); } }
					]
			},
			{
			-label => 'Help',
			-submenu =>	[
					{ -label => _('About'), -value => \&about_dialog },
					{ -label => _('License'), -value => \&license_dialog }
					]
			}
			]
);
########## Main window ##########


########## STAUS page ##########
my $win_status = $win_main->add(
	'win_status', 'Window',
	-border => 1,
	-title => _('Status'),
	-titlereverse => 0,
	-width => 78,
	-height => 19
);

$param{fuel} = '-';
$win_status->add( 'label_fuel', 'Label', -text => _('Fuel type:'), -y => 0 );
$param_label{fuel} = $win_status->add( 'label_fuel_value', 'Label', -text => $param{fuel}, -y => 0, -x => 14, -width => 15 );

$param{uptime} = '-';
$win_status->add( 'label_uptime', 'Label', -text => _('Uptime:'), -y => 1 );
$param_label{uptime} = $win_status->add( 'label_uptime_value', 'Label', -text => $param{uptime}, -y => 1, -x => 14, -width => 15 );

$param{sport} = 0;
$win_status->add( 'label_sport', 'Label', -text => _('Sport:'), -y => 2 );
$param_label{sport} = $win_status->add( 'label_sport_value', 'Checkbox', -label => '', -checked => $param{sport}, -y => 2, -x => 14);
$param_label{sport}->onFocus(sub {shift()->loose_focus});

$param{eco} = 0;
$win_status->add( 'label_eco', 'Label', -text => _('Eco:'), -y => 3 );
$param_label{eco} = $win_status->add( 'label_eco_value', 'Checkbox', -label => '', -checked => $param{eco}, -y => 3, -x => 14);
$param_label{eco}->onFocus(sub {shift()->loose_focus});

$param{lambda} = 0;
$win_status->add( 'label_lambda', 'Label', -text => _('Lambda:'), -y => 4 );
$param_label{lambda} = $win_status->add( 'label_lambda_value', 'Checkbox', -label => '', -checked => $param{lambda}, -y => 4, -x => 14);
$param_label{lambda}->onFocus(sub {shift()->loose_focus});

$param{mode} = '';
$win_status->add( 'label_mode', 'Label', -text => _('Mode:'), -y => 4, -x => 23 );
$param_label{mode} = $win_status->add( 'label_mode_value', 'Label', -text => $param{mode}, -y => 4, -x => 29, -width => 10 );

$param{speed} = 0;
$win_status->add( 'label_speed', 'Label', -text => _('Speed cur/avg:'), -y => 6 );
$param_label{speed} = $win_status->add( 'progressbar_speed_value', 'Progressbar', -pos => $param{speed}, -max => 300, -showvalue => 1, -nopercentage => 1, -nocenterline => 1, -y => 5, -x => 14, -width => 57 );

$param{speed_avg} = -1;
$param_label{speed_avg} = $win_status->add( 'label_speed_avg_value', 'Label', -text => '/ ' . $param{speed_avg}, -y => 6, -x => 71, -width => 5 );

$param{rpm} = 0;
$win_status->add( 'label_rpm', 'Label', -text => _('RPM:'), -y => 9 );
$param_label{rpm} = $win_status->add( 'progressbar_rpm_value', 'Progressbar', -pos => $param{rpm}, -max => 10000, -showvalue => 1, -nopercentage => 1, -nocenterline => 1, -y => 8, -x => 14 );

$param{etemp} = 0;
$win_status->add( 'label_etemp', 'Label', -text => _('Engine temp.:'), -y => 12 );
$param_label{etemp} = $win_status->add( 'progressbar_etemp_value', 'Progressbar', -pos => $param{etemp}, -max => 100, -showvalue => 1, -nopercentage => 1, -nocenterline => 1, -y => 11, -x => 14 );

$param{throttle} = 0;
$win_status->add( 'label_throttle', 'Label', -text => _('Throttle:'), -y => 15 );
$param_label{throttle} = $win_status->add( 'progressbar_throttle_value', 'Progressbar', -pos => $param{throttle}, -max => 100, -showvalue => 0, -nopercentage => 0, -nocenterline => 1, -y => 14, -x => 14 );

### logging ###
$win_status->add(
	'checkbox_log_file', 'Checkbox',
	-label => (defined($opts{l})) ? 'Log<-' : 'Log->',
	-onchange => \&log_start,
	-checked => (defined($opts{l})) ? 1 : 0,
	-y => 1,
	-x => 44
);
if (defined($opts{l})) {
	$win_status->getobj('checkbox_log_file')->onFocus(sub {shift()->loose_focus});
}
$win_status->add(
	'text_log_file', 'TextEntry',
	-text => (defined($opts{l})) ? $opts{l} : './log-' . time() . '.txt',
	-readonly => (defined($opts{l})) ? 1 : 0,
	-border => 1,
	-y => 0,
	-x => 53
);
### logging ###

$win_status->hide();
########## STATUS page ##########


########## DETAILS page ##########
my $win_details = $win_main->add(
	'win_details', 'Window',
	-border => 1,
	-title => _('Details'),
	-titlereverse => 0,
	-width => 78,
	-height => 19
);


# Injector
my $container_inj = $win_details->add(
	'container_inj', 'Container',
	-title => _('Injector'),
	-titlereverse => 0,
	-border => 1,
	-width => 24,
	-height => 7
);

$param{inj_open} = -1;
$container_inj->add( 'label_inj_open', 'Label', -text => _('Open:'), -y => 0 );
$param_label{inj_open} = $container_inj->add( 'label_inj_open_value', 'Label', -text => $param{inj_open}, -y => 0, -x => 17, -width => 10 );

$param{inj_capacity} = -1;
$container_inj->add( 'label_inj_capacity', 'Label', -text => _('Capacity:'), -y => 1 );
$param_label{inj_capacity} = $container_inj->add( 'label_inj_capacity_value', 'Label', -text => $param{inj_capacity}, -y => 1, -x => 17, -width => 10 );

$param{enrich_cur} = -1;
$container_inj->add( 'label_enrich_cur', 'Label', -text => _('Enrich cur.:'), -y => 2 );
$param_label{enrich_cur} = $container_inj->add( 'label_enrich_cur_value', 'Label', -text => $param{enrich_cur}, -y => 2, -x => 17, -width => 10 );

$param{enrich_avg} = -1;
$container_inj->add( 'label_enrich_avg', 'Label', -text => _('Enrich avg.:'), -y => 3 );
$param_label{enrich_avg} = $container_inj->add( 'label_enrich_avg_value', 'Label', -text => $param{enrich_avg}, -y => 3, -x => 17, -width => 10 );


# Lambda
my $container_lam = $win_details->add(
	'container_lam', 'Container',
	-title => 'Lambda',
	-titlereverse => 0,
	-border => 1,
	-x => 24,
	-width => 36,
	-height => 7
);

$param{lambda_trimmer} = -1;
$container_lam->add( 'label_lambda_trimmer', 'Label', -text => _('Trimmer:'), -y => 0, -x => 0 );
$param_label{lambda_trimmer} = $container_lam->add( 'label_lambda_trimmer_value', 'Label', -text => $param{lambda_trimmer}, -y => 0, -x => 17, -width => 15 );

$param{lambda_in_min} = -1;
$param{lambda_in_mid} = -1;
$param{lambda_in_max} = -1;
$container_lam->add( 'label_lambda_in_pot', 'Label', -text => _('IN min/mid/max:'), -y => 1, -x => 0 );
$param_label{lambda_in_pot} = $container_lam->add( 'label_lambda_in_pot_value', 'Label',
					-text => $param{lambda_in_min} . '/' . $param{lambda_in_mid} . '/' . $param{lambda_in_max},
					-y => 1, -x => 17, -width => 15 );

$param{lambda_out_min} = -1;
$param{lambda_out_mid} = -1;
$param{lambda_out_max} = -1;
$container_lam->add( 'label_lambda_out_pot', 'Label', -text => _('OUT min/mid/max:'), -y => 2, -x => 0 );
$param_label{lambda_out_pot} = $container_lam->add( 'label_lambda_out_pot_value', 'Label',
					-text => $param{lambda_out_min} . '/' . $param{lambda_out_mid} . '/' . $param{lambda_out_max},
					-y => 2, -x => 17, -width => 15 );

$param{lambda_in_calc} = -1;
$param{lambda_out_calc} = -1;
$container_lam->add( 'label_lambda_calc_pot', 'Label', -text => _('IN/OUT calc.:'), -y => 3, -x => 0 );
$param_label{lambda_calc_pot} = $container_lam->add( 'label_lambda_calc_pot_value', 'Label',
					-text => $param{lambda_in_calc} . '/' . $param{lambda_out_calc},
					-y => 3, -x => 17, -width => 15 );

$param{potential_in} = -1;
$container_lam->add( 'label_potential_in', 'Label', -text => _('IN potential:'), -y => 4 );
$param_label{potential_in} = $container_lam->add( 'label_potential_in_value', 'Label', -text => $param{potential_in}, -y => 4, -x => 17, -width => 15 );

# Consumption
my $container_cons = $win_details->add(
	'container_cons', 'Container',
	-title => _('Consumption'),
	-titlereverse => 0,
	-border => 1,
	-y => 7,
	-width => 30,
	-height => 7
);

$param{cons_pred} = -1;
$container_cons->add( 'label_cons_pred', 'Label', -text => _('Predicted:'), -y => 0 );
$param_label{cons_pred} = $container_cons->add( 'label_cons_pred_value', 'Label', -text => $param{cons_pred}, -y => 0, -x => 17, -width => 10 );

$param{cons_cur} = -1;
$container_cons->add( 'label_cons_cur', 'Label', -text => _('Current:'), -y => 1 );
$param_label{cons_cur} = $container_cons->add( 'label_cons_cur_value', 'Label', -text => $param{cons_cur}, -y => 1, -x => 17, -width => 10 );

$param{cons_avg_1} = -1;
$container_cons->add( 'label_cons_avg_1', 'Label', -text => _('Average / 1km:'), -y => 2 );
$param_label{cons_avg_1} = $container_cons->add( 'label_cons_avg_1_value', 'Label', -text => $param{cons_avg_1}, -y => 2, -x => 17, -width => 10 );

$param{cons_avg_30} = -1;
$container_cons->add( 'label_cons_avg_30', 'Label', -text => _('Average / 30km:'), -y => 3 );
$param_label{cons_avg_30} = $container_cons->add( 'label_cons_avg_30_value', 'Label', -text => $param{cons_avg_30}, -y => 3, -x => 17, -width => 10 );

# Travel
my $container_travel = $win_details->add(
	'container_travel', 'Container',
	-title => _('Travel'),
	-titlereverse => 0,
	-border => 1,
	-y => 7,
	-x => 30,
	-width => 30,
	-height => 7
);

$param{km} = -1;
$container_travel->add( 'label_km', 'Label', -text => _('Traveled km:'), -y => 0 );
$param_label{km} = $container_travel->add( 'label_km_value', 'Label', -text => $param{km}, -y => 0, -x => 18, -width => 10 );

$param{km_start} = -1;
$container_travel->add( 'label_km_start', 'Label', -text => _('Trav. km (start):'), -y => 1 );
$param_label{km_start} = $container_travel->add( 'label_km_start_value', 'Label', -text => $param{km_start}, -y => 1, -x => 18, -width => 10 );

$param{co2_save_1} = -1;
$container_travel->add( 'label_co2_save_1', 'Label', -text => _('CO2 save / 1km:'), -y => 2 );
$param_label{co2_save_1} = $container_travel->add( 'label_co2_save_1_value', 'Label', -text => $param{co2_save_1}, -y => 2, -x => 18, -width => 10 );

$param{co2_save_start} = -1;
$container_travel->add( 'label_co2_save_start', 'Label', -text => _('CO2 save (start):'), -y => 3 );
$param_label{co2_save_start} = $container_travel->add( 'label_co2_save_start_value', 'Label', -text => $param{co2_save_start}, -y => 3, -x => 18, -width => 10 );

$param{co2_save_sum} = -1;
$container_travel->add( 'label_co2_save_sum', 'Label', -text => _('CO2 save (sum):'), -y => 4 );
$param_label{co2_save_sum} = $container_travel->add( 'label_co2_save_sum_value', 'Label', -text => $param{co2_save_sum}, -y => 4, -x => 18, -width => 10 );

# some extra stuff
$win_details->add( 'label_enrich_cur_progressbar', 'Label', -text => _('Enrich cur.:'), -y => 15 );
$param_label{enrich_cur_progressbar} = $win_details->add( 'progressbar_enrich_cur_value', 'Progressbar', -pos => $param{enrich_cur}, -max => 100, -showvalue => 0, -nopercentage => 0, -nocenterline => 1, -y => 14, -x => 12, -width => 48 );

# notes
my $text_details_notes = $win_details->add(
	'text_details_notes', 'TextEditor',
	-title => _('Notes'),
	-titlereverse => 0,
	-text => '',
	-border => 1,
	-x => 60,
	-y => 0,
	-height => 16
);
$win_details->add(
	'button_details_notes_save', 'Buttonbox',
	-buttons =>	[
			{
			-label => _('Save notes'),
			-onpress => \&save_notes_dialog
			}
			],
	-x => 63,
	-y => 16
);


# XXX another inconveniency
# Exclude the containers from the focus order, otherwise
# some label will get the focus in the first container,
# and won't give it back...
$win_details->set_focusorder(	'text_details_notes',
				'button_details_notes_save'
);

$win_details->hide();
########## DETAILS page ##########


########## CONTROL page ##########
my $win_control = $win_main->add(
	'win_control', 'Window',
	-title => _('Control'),
	-titlereverse => 0,
	-border => 1,
	-width => 78,
	-height => 19
);

$win_control->add( 'label_command_filter', 'Label', -text => _('Command filter:') );
my $text_command_filter = $win_control->add(
		'text_command_filter', 'TextEntry',
		-text => '',
		-regexp => '/^[A-Z]*$/',
		-toupper => 1,
		-reverse => 1,
		-homeonblur => 0,
		-y => 0,
		-x => 16,
		-onchange => \&filter_command_list
);

# populate the commands' help hash, if it is present
my %command_help = ();
my $help_file = 'e85power.help';
if (open(HELP_FILE, '<', $help_file)) {
	%command_help = do $help_file;
	close(HELP_FILE);
}

my %command_list = (
	CGETADC => undef,
	CGETANALOG => undef,
	CGETDATA => undef,
	CGETERROR => undef,
	CGETFUEL => undef,
	CGETICT => undef,
	CGETLLIST => undef,
	CGETMODE => undef,
	CGETPARAM => undef,
	CGETPOWER => undef,
	CGETRICH => undef,
	CGETRPM => undef,
	CGETSTAT => undef,
	CGETSYS => undef,
	CGETTABLE1 => undef,
	CGETTABLE2 => undef,
	CGETTABLE3 => undef,
	CGETTABLE4 => undef,
	CGETTABLE5 => undef,
	CGETTABLE6 => undef,
	CGETTEMP => undef,
	CGETTIME => undef,
	CGETTPS => undef,
	CSETCAPMAX => 'xx',
	CSETCCM => undef,
	CSETCOLD => 'xx',
	CSETDIST => undef,
	CSETECO => 'x',
	CSETFALLTIME => 'xx',
	CSETFIRST => 'x,y,zz',
	CSETICTCOLD => undef,
	CSETICTHOT => undef,
	CSETICTPARAM => 'xxx,yyy',
	CSETIDLE => undef,
	CSETINIT => undef,
	CSETINJAUTO => 'x,yyy',
	CSETINJPARAM => 'xx,yy,zz,w',
	CSETLAM => 'xxx,yy',
	CSETLAMMUL => 'xx',
	CSETLAMOFFS => 'xxx,yyy',
	CSETLAMRISE => 'xx,yy',
	CSETLAMTYPE => 'x',
	CSETLAMWIN => 'xx,yy',
	CSETMODE => 'x',
	CSETMON => undef,
	CSETONTIMEREF => 'xx',
	CSETRPM => 'xxxx',
	CSETSILENT => undef,
	CSETSPEED => undef,
	CSETSPORT => 'x',
	CSETSWMODE => undef,
	CSETTABFILL => 'x,yyy',
	CSETTABPOINT => 'x,yy,zzz',
	CSETTARGETLAM => 'xx,yy',
	CSETTPSMAX => undef,
	CSETTPSMIN => undef,
	CSETTPSPOINT => 'xx,yy',
	CSETTRIM => 'x,y,zzzz'
);
my %command_list_filtered = ();
my @popupmenu_command_list_values = ();
my $idx = 0;
# populate the filtered command list
foreach (sort(keys %command_list)) {
	$command_list_filtered{++$idx} = $_;
	push @popupmenu_command_list_values, $idx;
}
@popupmenu_command_list_values = ( 1..$idx );

$win_control->add( 'label_command_list', 'Label', -text => _('Command:'), -x => 7, -y => 1 );
my $popupmenu_command_list = $win_control->add(
	'popupmenu_command_list', 'Popupmenu',
	-values => \@popupmenu_command_list_values,
	-selected => 0,
	-labels => \%command_list_filtered,
	-y => 1,
	-x => 16,
	-width => 15
);

my $button_control = $win_control->add(
	'button_control', 'Buttonbox',
	-buttons =>	[
			{
			-label => _('Send'),
			-value => 'send',
			-onpress => (defined($opts{l})) ? sub {
				$cui->status( -message => _("Currently in log file mode") ); sleep 1; $cui->nostatus();
			} : \&send_button
			},
			{
			-label => _('Help'),
			-value => 'help',
			-onpress => \&help_button
			}
			],
	-x => 33,
	-y => 1
);

my $response_box = $win_control->add(
	'response_box', 'TextViewer',
	-border => 1,
	-titlereverse => 0,
	-title => _('Response'),
	-wrapping => 1,
	-vscrollbar => 1,
	-x => 0,
	-y => 2
);
$response_box->beep_off();

$win_control->hide();
########## CONTROL page ##########


########## usage info on the bottom ########## 
$win_main->add(
	'label_usage', 'Label',
	-text => "F1-F3: " . _('Pages') . "  ^X: " . _('Menu'),
	-border => 1,
	-x => 0,
	-y => -1
);
########## usage info on the bottom ########## 

########## software version on the bottom ########## 
$param_label{sw_version} = $win_main->add(
	'label_sw_version_value', 'Label',
	-text => 'SW: ' . (defined($param{sw_version}) ? $param{sw_version} : '-'),
	-border => 1,
	-x => 25,
	-y => -1,
	-width => 22
);
########## software version on the bottom ########## 

########## serial device status on the bottom ########## 
my $label_status = $win_main->add(
	'label_status', 'Label',
	-text => _("Disconnected") . "($serial_device)",
	-border => 1,
	-x => -1,
	-y => -1
);
########## serial device status on the bottom ########## 


if (defined($opts{l})) {
	log_file_setup();
} else {
	serial_port_setup();
}


show_page(0);


########## key bindings ########## 
$cui->set_binding(sub {$menu->focus()}, "\cX");
$cui->set_binding(\&quit_dialog, "\cQ", "\cC");
$cui->set_binding(sub { show_page(0); }, KEY_F(1));
$cui->set_binding(sub { show_page(1); }, KEY_F(2));
$cui->set_binding(sub { show_page(2); }, KEY_F(3));
########## key bindings ########## 


$cui->mainloop();


sub update_info
{
# The device outputs only one dataline, so we can not turn on every
# monitoring command (eg.: CSETMON + CGETDATA + CGETSTAT) to get every
# data we need.
# That is why we give every monitor command a chance to output its data
# and we process them in their time-slice. Fortunatelly some data appears
# in both command's output, so we don't miss one second of updating with eg.
# the RPM and the ECO/Sport mode infos.
# We could update more often (and get every data under eg. one second) but
# Curses::UI's set_timer() only understands seconds as its timeout.

	if ($monitoring eq 'CGETSTAT') {
		$monitoring = 'CGETDATA';
	} elsif ($monitoring eq 'CGETDATA') {
		$monitoring = 'CGETSTAT';
	}
	send_command($monitoring, 1);

	( $param{uptime} ) = send_command('CGETTIME', 1);


	# if reading from log file, overwrite the data from it
	if (defined($opts{l})) {
		if (eof(LOG_INPUT)) {
			close(LOG_INPUT);
			$cui->disable_timer('timer_update_info');

			$retval = $cui->dialog(
				-title => _("Log file"),
				-message => _("End of log file."),
				-buttons => ['ok'],
			);

			return;
		} else {
			$line_monitor = <LOG_INPUT>;
			chomp($line_monitor);
			$param{uptime} = $line_monitor;
		}
	}


	update_info_monitor();

	if (defined($param{uptime})  &&  $param{uptime} =~ '^TIME=') {
		( undef, $param{uptime} ) = split(/=/, $param{uptime});

		$param{uptime} /= 10000;
		my $hour = int($param{uptime} / 60 / 60); $param{uptime} -= $hour * 60 * 60;
		my $min = int($param{uptime} / 60); $param{uptime} -= $min * 60;
		my $sec = int($param{uptime});
		$param{uptime} = sprintf("%02d:%02d.%02d", $hour, $min, $sec);
		$param_label{uptime}->text($param{uptime});
	}


	$win_status->intellidraw();
	$win_details->intellidraw();
}

sub update_info_monitor
{
	return unless length($line_monitor);


	if ($line_monitor =~ m/^\Q[S]\E/) {
		# [S]a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s[E]

		$line_monitor =~ s/\[[SE]+\]//g;	# remove ^[S] and [E]$

		($param{km}, $param{km_start}, $param{speed}, $param{speed_avg}, $param{cons_cur}, undef, $param{cons_avg_1},
		$param{cons_avg_30}, $param{rpm}, $param{cons_pred}, $param{fuel}, $param{eco}, $param{sport},
		$param{lambda}, $param{co2_save_1}, $param{co2_save_start}, $param{co2_save_sum}, undef, undef) = split(/\//, $line_monitor);
	} elsif ($line_monitor =~ m/^\Q[D]\E/) {
		# [D]0/0/2000/0/2000/0/0.00/0.00/0/34/0/0.00/26/0/24/0/1/69/0/119/1/0/0/0[E]

		$line_monitor =~ s/\[[DE]+\]//g;	# remove ^[D] and [E]$

		($param{lambda_in_mid}, $param{lambda_out_mid}, $param{lambda_in_min}, $param{lambda_in_max},
		$param{lambda_out_min}, $param{lambda_out_max}, $param{lambda_in_calc}, $param{lambda_out_calc},
		$param{lambda}, $param{lambda_trimmer}, $param{rpm}, $param{inj_open}, $param{enrich_cur}, 
		$param{enrich_avg}, $param{cons_pred}, $param{inj_capacity}, $param{fuel}, $param{etemp},
		$param{throttle}, $param{potential_in}, $param{mode}, $param{sport}, $param{eco}, undef) = split(/\//, $line_monitor);
	}


	$param_label{km}->text($param{km});
	$param_label{km_start}->text($param{km_start});

	$param_label{speed}->pos($param{speed});
	$param_label{speed_avg}->text('/ ' . $param{speed_avg});

	$param_label{cons_cur}->text($param{cons_cur});
	$param_label{cons_avg_1}->text($param{cons_avg_1});
	$param_label{cons_avg_30}->text($param{cons_avg_30});

	$param_label{cons_pred}->text($param{cons_pred});

	if ($param{fuel} eq 0) {
		$param{fuel} = _('Petrol');
	} elsif ($param{fuel} eq 1) {
		$param{fuel} = _('Mix');
	} elsif ($param{fuel} eq 2) {
		$param{fuel} = _('E85');
	}
	$param_label{fuel}->text($param{fuel});

	$param{eco} ? $param_label{eco}->check : $param_label{eco}->uncheck;

	$param{sport} ? $param_label{sport}->check : $param_label{sport}->uncheck;

	$param{lambda} ? $param_label{lambda}->check : $param_label{lambda}->uncheck;

	$param_label{co2_save_1}->text($param{co2_save_1});
	$param_label{co2_save_start}->text($param{co2_save_start});
	$param_label{co2_save_sum}->text($param{co2_save_sum});

	$param_label{lambda_in_pot}->text($param{lambda_in_min} . '/' . $param{lambda_in_mid} . '/' . $param{lambda_in_max});
	$param_label{lambda_out_pot}->text($param{lambda_out_min} . '/' . $param{lambda_out_mid} . '/' . $param{lambda_out_max});
	$param_label{lambda_calc_pot}->text($param{lambda_in_calc} . '/' . $param{lambda_out_calc});

	$param_label{lambda_trimmer}->text($param{lambda_trimmer});

	$param_label{rpm}->pos($param{rpm});

	$param_label{inj_open}->text($param{inj_open});

	$param_label{enrich_cur}->text($param{enrich_cur});
	$param_label{enrich_cur_progressbar}->pos($param{enrich_cur});
	$param_label{enrich_avg}->text($param{enrich_avg});

	$param_label{inj_capacity}->text($param{inj_capacity});

	$param_label{etemp}->pos($param{etemp});

	$param_label{throttle}->pos($param{throttle});

	$param_label{potential_in}->text($param{potential_in});

	# XXX Ezek a szovegek nem biztos hogy jok...
	if ($param{mode} eq 0) {
		$param{mode} = _('OFF');
	} elsif ($param{mode} eq 1) {
		$param{mode} = _('Auto');
	} elsif ($param{mode} eq 2) {
		$param{mode} = _('Sport');
	} elsif ($param{mode} eq 3) {
		$param{mode} = _('RPM Table 1');
	} elsif ($param{mode} eq 4) {
		$param{mode} = _('RPM + TPS Table 1');
	} elsif ($param{mode} eq 5) {
		$param{mode} = _('RPM Table 2');
	} elsif ($param{mode} eq 6) {
		$param{mode} = _('RPM + TPS Table 2');
	} elsif ($param{mode} eq 7) {
		$param{mode} = _('Fix');
	}
	$param_label{mode}->text($param{mode});


	$win_status->intellidraw();
	$win_details->intellidraw();
}

sub getparam
{
# This reads every CSET* command's current parameter.

# XXX BUG: my device seems to leave out the last few (RPMDIV,
# SPEEDDIV, CCM, SWMODE, TRIM, FIRST) parameters, and I
# can see these last few lines very rarely in CGETPARAM's
# output. This may be because of a timeout caused by a faulty
# or too long USB cable and/or the car's/laptop's electric
# circuit's low quality.

	my @getparam = ();


	@getparam = send_command('CGETPARAM', 1);
	foreach (@getparam) {
		if (m/SW VERSION:/) {
			s/^.*SW VERSION: //;
			$param{sw_version} = $_;
			$param_label{sw_version}->text('SW: ' . $param{sw_version});
			$param_label{sw_version}->draw();
		}

		my ( $cmd_temp, $current_value ) = split(/=/);
		$cmd_temp = 'CSET' . $cmd_temp;
		if (defined($command_list{$cmd_temp})) {
			$command_list{$cmd_temp} = $current_value;
		}
	}
}

sub send_command
{
	my $cmd = shift;
	my $auto = shift;
	my @answer = ();


	if (defined($PortObj)) {
		$written = $PortObj->write($cmd . "\r\n");
		if (defined($written)) {
			if ($written == length($cmd . "\r\n")) {
				@answer = read_response($cmd, $auto);
				if (!$auto) {
					$response_box->text($response_box->get() . "\n" . '> ' . $cmd);

					if (defined($answer[0])) {
						foreach (@answer) {
							$response_box->text($response_box->get() . "\n" . '= ' . $_);
						}
					} else {
						$response_box->text($response_box->get() . "\n" . "! '$cmd': " . _("failed to read response"));
					}
				}
			} else {
				$response_box->text($response_box->get() . "\n" . "! '$cmd': " . _("sending failed (short write)")) unless $auto;
			}
		} else {
			$response_box->text($response_box->get() . "\n" . "! '$cmd': " . _("sending failed (write error)")) unless $auto;
		}
	} else {
		$response_box->text($response_box->get() . "\n" . "! '$cmd': " . _("sending failed (not connected)")) unless $auto;
	}

	if (!$auto) {
		# intentionally twice ...
		$response_box->pos(length($response_box->get())); $response_box->cursor_pagedown();
		$response_box->pos(length($response_box->get())); $response_box->cursor_pagedown();

		$response_box->intellidraw();
	}

	return(@answer);
}

sub read_response
{
	my $cmd = shift;
	my $auto = shift;
	my $line = undef;
	my $i = 0;
	my $timeout = 500;	# Allow this maximum amount of initial reading, then assume something went wrong. This is the while() loop's maximum allowed running count.
	my @response = ();


	if (defined($PortObj)) {
		# The thing is, we don't poll especially for CSET{DATA,STAT}'s output,
		# because that comes prepended before any other command's answer anyway.
		# So we make sure, that the set_timer()'d update_info() issues minimum one
		# command which is useful for our Status page, and collect CSET{DATA,STAT}'s '^[DS] ...'
		# answer during the polling of every other - automatically issued - command's answer.
		# Then we cut that '[DS] ...' from the input, update the $line_monitor variable
		# which will be fed to update_info_monitor() in update_info(), and process the rest of the
		# line as the answer to our originally issued command.

		# Initial reading; we try to wait for the issued command's answer.
		while (!length($line)) {
			$line = $PortObj->lookfor();

			$i++;

			# otherwise if timeout is reached, assume something went wrong
			if ((!defined($line))  ||  ($i >= $timeout)) {
				$cui->disable_timer('timer_update_info');

				$PortObj->close();
				$PortObj = undef;

				$label_status->text(_('Disconnected') . "($serial_device)");
				$label_status->draw;

				$retval = $cui->dialog(
					-title => _('Serial device') . "($serial_device)",
					-message => _("Serial line seems to be dead.\nReconnect?"),
					-buttons => ['yes', 'no'],
				);

				serial_port_setup() if $retval;


				return(@response);
			}
		}

		# if we have input, read everything until ''
		while (length($line)) {
			$line =~ s/[\x0a\x0d]*//g;	# remove every newline

			# if it's a monitoring line, extract the data from it
			if ($line =~ m/\[[DS]\]/) {
				$line_monitor = $line;

				# $line_monitor will be only the CGET{DATA,STAT}'s output
				$line_monitor =~ s/(.*)(\[[DS]\].*\Q[E]\E)(.*)/$2/;
				# XXX DEBUG
				print STDERR "\$line_monitor($cmd): '$line_monitor'\n";

				# $line will be everything other than CGET{DATA,STAT}'s output
				$line =~ s/\[[DS]\].*\Q[E]\E//;
			}

			# XXX DEBUG
			print STDERR "\$line($cmd): '$line'\n";
			push @response, $line unless !length($line);

			$line = $PortObj->lookfor();
		}

		if ($logging) {
			# log CGET{DATA,STAT}'s output (if requested)
			print LOG_FILE "$line_monitor\n" if length($line_monitor);
			# log GETTIME's output too (if requested)
			print LOG_FILE "$response[0]\n" if ($response[0] =~ m/^TIME=/);
		}
	}


	return(@response);
}

sub filter_command_list
{
	my $idx = 0;
	my $filter = $text_command_filter->get();


	# empty the cmd list
	%command_list_filtered = ();
	@popupmenu_command_list_values = ();

	# repopulate the command list with only the commands which match the user supplied filter
	foreach (keys %command_list) {
		if (m/^.*$filter.*$/) {
			$command_list_filtered{++$idx} = $_;
			push @popupmenu_command_list_values, $idx;
		}
	}

	if ($idx <= 0) {
		%command_list_filtered = ( 1 => '-' );
		@popupmenu_command_list_values = ( 1 );
	}


	# to modify the '-values' option, we must recreate the popupmenu
	# XXX pretty inconvenient...
	$win_control->delete('popupmenu_command_list');
	$popupmenu_command_list = $win_control->add(
		'popupmenu_command_list', 'Popupmenu',
		-values => \@popupmenu_command_list_values,
		-selected => 0,
		-labels => \%command_list_filtered,
		-y => 1,
		-x => 16,
		-width => 15
	);

	# reorder the focus list, because the popupmenu was readded
	# XXX pretty inconvenient...
	$win_control->set_focusorder(	'text_command_filter',
					'popupmenu_command_list',
					'button_control',
					'response_box'
	);

	
	$text_command_filter->focus();
}

sub send_button
{
	my $value = $popupmenu_command_list->get();
	if (!defined($value)) {
		return;
	}

	my $cmd = $command_list_filtered{$value};
	if (length($cmd)) {
		if ($cmd eq '-') {
			return;
		}
	} else {
		return;
	}


	my $cancel = 0;

	# if there are parameters to the command, ask for them
	if (defined($command_list{$cmd})) {
		# read current CSET* values
		getparam();

		my $container_command_parameter = $win_main->add(
			'container_command_parameter', 'Container',
			-title => $cmd,
			-border => 1,
			-x => 2,
			-y => 4,
			-width => 42,
			-height => 6
		);

		$container_command_parameter->add(
			'textentry_command_parameter', 'TextEntry',
			-text => $command_list{$cmd},	# the text field will contain the actual values for the CSET* command. (getparam())
			-border => 1,
			-vscrollbar => 1,
			-height => 4
		);
		$container_command_parameter->add(
			'command_parameter_button', 'Buttonbox',
			-buttons =>	[
					{
					-label => '< ' . _('Send') . ' >',
					-onpress => sub {
							$container_command_parameter->loose_focus();
							$win_main->delete('container_command_parameter');
							$win_main->draw();
							$cancel = 0;
							$cmd .= '=' . $container_command_parameter->getobj('textentry_command_parameter')->text();
						}
					},
					{
					-label => '< ' . _('Cancel') . ' >',
					-onpress => sub {
							$container_command_parameter->loose_focus();
							$win_main->delete('container_command_parameter');
							$win_main->draw();
							$cancel = 1;
						}
					}
					],
			-x => -1,
			-y => -1,
			-width => 20
		);
		$win_main->getobj('container_command_parameter')->show();
		$win_main->getobj('container_command_parameter')->modalfocus();
	}

	send_command($cmd, 0) unless ($cancel);
}

sub help_button
{
	my $value = $popupmenu_command_list->get();
	if (!defined($value)) {
		return;
	}

	my $cmd = $command_list_filtered{$value};
	if (length($cmd)) {
		if ($cmd eq '-') {
			return;
		}
	} else {
		return;
	}

	$cui->dialog(
		-title => _('Help') . " ($cmd)",
		-message => length($command_help{$cmd}) ? $command_help{$cmd} : _('No help available.'),
		-buttons => ['ok'],
	);
}

sub log_start
{
	my $log_file = $win_status->getobj('text_log_file')->get();


	if ($win_status->getobj('checkbox_log_file')->get()) {
		if (open(LOG_FILE, '>>', $log_file)) {
			$logging = 1;
			$cui->status( -message => _('Logging started') ); sleep 1; $cui->nostatus();
		} else {
			$cui->error(
				-title => _('Logging'),
				-message => _("Can't open") . " '$log_file': $!"
			);
			$win_status->getobj('checkbox_log_file')->uncheck();
		}
	} else {
		$cui->status( -message => _('Logging stopped') ); sleep 1; $cui->nostatus();
		close(LOG_FILE);
		$logging = 0;
	}
}

sub log_file_setup
{
	if (open(LOG_INPUT, '<', $opts{l})) {
		$cui->set_timer('timer_update_info', \&update_info, 1);
		$cui->set_binding(\&update_info, KEY_F(5));
	} else {
		$cui->error(
			-title => _('Log file'),
			-message => _("Couldn't open") . " '$opts{l}': $!"
		);
		exit(1);
	}
}

sub serial_port_setup
{
	if (defined($PortObj)) {
		$retval = $cui->dialog(
			-title => _('Reconnect'),
			-message => _('Reconnect to') . "$serial_device?",
			-buttons => ['no', 'yes'],
		);

		if ($retval) {
			$PortObj->close();
			$PortObj = undef;

			$label_status->text(_('Disconnected') . "($serial_device)");
			$label_status->draw;
		} else {
			return;
		}
	}

	$PortObj = new Device::SerialPort($serial_device, 0, undef);
	my $error = $!;

	if (defined($PortObj)) {
		# connected
		$PortObj->baudrate(115200);
		$PortObj->databits(8);
		$PortObj->parity("none");
		$PortObj->stopbits(1);
		$PortObj->handshake("none");	# rts, xoff, none

		$PortObj->buffers(4096, 4096); 

		$PortObj->are_match("\r\n"); 

		$label_status->text(_('Connected') . "($serial_device)");
		$label_status->intellidraw;

		# Write and read something to 'wake' the device.
		# Sometimes the very first command gets swallowed :)
		$PortObj->write("CGETPARAM\r\n");
		$PortObj->lookfor(); $PortObj->lookfor();
		$PortObj->lookclear();

		# read current CSET* values
		getparam();

		$cui->set_timer('timer_update_info', \&update_info, 1);
	} else {
		# couldn't connect
		$cui->disable_timer('timer_update_info');

		$cui->error(
			-title => _('Serial device') . " ($serial_device)",
			-message => _("Can't connect") . ":\n$error"
		);
	}
}

sub show_page
{
	my $page = shift;


	if ($page == 0) {
		$cui->disable_timer('timer_update_info');
		$cui->set_timer('timer_update_info', \&update_info, 1);

		$win_details->hide();
		$win_control->hide();

		$win_status->show();
		$win_status->focus();

		$win_main->draw();
	} elsif ($page == 1) {
		$cui->disable_timer('timer_update_info');
		$cui->set_timer('timer_update_info', \&update_info, 1);

		$win_status->hide();
		$win_control->hide();

		$win_details->show();
		$text_details_notes->focus();

		$win_main->draw();
	} elsif ($page == 2) {
		send_command('CSETSILENT', 1);

		# read current CSET* values
		getparam();

		$cui->disable_timer('timer_update_info');

		$win_status->hide();
		$win_details->hide();

		$win_control->show();
		$text_command_filter->focus();

		$win_main->draw();
	}
}

sub save_notes_dialog
{
	my $file = $cui->savefilebrowser( -file => '' );
	return unless defined $file;

	if (open(NOTES_FILE, '>', $file)) {
		print NOTES_FILE $text_details_notes->text();

		if (close(NOTES_FILE)) {
			$cui->dialog( -message => _('Saved') . " '$file'" );
		} else {
			$cui->error( -message => _('Error on closing file') . " '$file':\n$!" );
		}
	} else {
		$cui->error( -message => _("Can't write to") . " '$file':\n$!" );
	}
}

sub quit_dialog
{
	$retval = $cui->dialog(
		-title => _('Quit'),
		-message => _('Do you really want to quit?'),
		-buttons => ['no', 'yes'],
	);

	if ($retval) {
		send_command('CSETSILENT', 1);
		exit(0);
	}
}

sub about_dialog
{
	$cui->dialog(
		-title => _('About'),
		-message => "E85 Power Kit controller 1.0\nAuthor: Lévai Dániel <leva\@ecentrum.hu>\n\nMore info: www.e85power.hu",
		-buttons => ['ok'],
	);
}

sub license_dialog
{
	$win_main->add(
		'license_container', 'Container',
		-title => _('License') . ' (BSD)',
		-border => 1,
		-height => 22
	);
	$win_main->getobj('license_container')->add(
		'license_message', 'TextViewer',
		-text => $bsd_license,
		-border => 1,
		-vscrollbar => 1,
		-height => 17
	);
	$win_main->getobj('license_container')->add(
		'license_button', 'Buttonbox',
		-buttons =>	[
				{
				-label => '< OK >',
				-shortcut => 'o',
				-onpress => sub {
						$win_main->getobj('license_container')->loose_focus();
						$win_main->delete('license_container');
						$win_main->draw();
					}
				}
				],
		-pad => 1,
		-x => -1,
		-y => -1,
		-width => 8
	);
	$win_main->getobj('license_container')->show();
	$win_main->getobj('license_container')->modalfocus();
}

sub _
{
	my $msg = shift;
	my %messages = ();


	return($msg) unless defined($intl_file);
	return($msg) unless open(DUMMY, '<', $intl_file); close(DUMMY);

	%messages = do $intl_file;

	defined($messages{$msg}) ? return($messages{$msg}) : return($msg);
}

sub HELP_MESSAGE
{
	print "$0 [-d serial_device] [-l log_file] [-c] [-r] [-h]\n";
	print ' -d : ' . _('use the specified serial device') . "\n";
	print ' -l : ' . _('read input from the specified log file') . "\n";
	print ' -i : ' . _('specify the language file to use') . "\n";
	print ' -c : ' . _('curses compatibility mode') . "\n";
	print ' -r : ' . _('color support') . "\n";
	print ' -v : ' . _('version information') . "\n";
	print ' -s : ' . _('license') . "\n";
	print ' -h : ' . _('this help') . "\n";
	exit(0);
}

sub VERSION_MESSAGE
{
	print "E85 Power Controller 1.0\n";
	print "LEVAI Daniel <leva\@ecentrum.hu>\n";
	print _('See the -s option for copying information.') . "\n";
	HELP_MESSAGE();
	exit(0);
}

sub LICENSE_MESSAGE
{
	print $bsd_license;
	exit(0);
}
