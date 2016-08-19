package Selenium::UserAgent;

# ABSTRACT: Emulate mobile devices by setting user agents when using webdriver
use Moo;
use JSON;
use Cwd qw/abs_path/;
use Carp qw/croak/;
use List::Util 1.33 qw/any/;
use Selenium::Firefox::Profile;

=for markdown [![Build Status](https://travis-ci.org/gempesaw/Selenium-UserAgent.svg?branch=master)](https://travis-ci.org/gempesaw/Selenium-UserAgent)

=head1 SYNOPSIS

    my $sua = Selenium::UserAgent->new(
        browserName => 'chrome',
        agent => 'iphone'
    );

    my $caps = $sua->caps;
    my $driver = Selenium::Remote::Driver->new_from_caps(%$caps);

=head1 DESCRIPTION

This package will help you test your websites on mobile devices by
convincing your browsers to masquerade as a mobile device. You can
start up Firefox or Chrome with the same user agents that your mobile
browsers would send, along with the same screen resolution and layout.

Although the experience may not be 100% the same as manually testing
on an actual mobile device, the advantage of testing this way is that
you hardly need any additional infrastructure if you've already got a
webdriver testing suite set up.

=attr browserName

Required: specify which browser type to use. Currently, we only
support C<Chrome> and C<Firefox>.

    my $sua = Selenium::UserAgent->new(
        browserName => 'chrome',
        agent => 'ipad'
    );

=cut

has browserName => (
    is => 'rw',
    required => 1,
    coerce => sub {
        my $browser = $_[0];

        croak 'Only chrome and firefox are supported.'
          unless $browser =~ /chrome|firefox/;
        return lc($browser)
    }
);

=attr agent

Required: specify which mobile device type to emulate. Your options
are:

    iphone4
    iphone5
    iphone6
    iphone6plus
    ipad_mini
    ipad
    galaxy_s3
    galaxy_s4
    galaxy_s5
    galaxy_note3
    nexus4
    nexus9
    nexus10

These are more specific than the choices for device agent in previous
versions of this module, but to preserve existing functionality, the
following conversions are made to the deprecated device selections:

    iphone         => "iphone4"
    ipad_seven     => "ipad"
    android_phone  => "nexus4"
    android_tablet => "nexus10"

The exact resolutions and user agents are included in the source and
in the L<github
repo|https://github.com/gempesaw/Selenium-UserAgent/blob/master/lib/Selenium/devices.json>;
they're vetted against the L<values that Mozilla uses for
Firefox|https://code.cdn.mozilla.net/devices/devices.json>.

Usage looks like:

    my $sua = Selenium::UserAgent->new(
        browserName => 'chrome',
        agent => 'ipad'
    );

=cut

has agent => (
    is => 'rw',
    required => 1,
    coerce => sub {
        my $agent = $_[0];

        my @valid = qw/
                          iphone4
                          iphone5
                          iphone6
                          iphone6plus
                          ipad_mini
                          ipad
                          galaxy_s3
                          galaxy_s4
                          galaxy_s5
                          galaxy_note3
                          nexus4
                          nexus9
                          nexus10
                      /;

        my $updated_agent = _convert_deprecated_agent( $agent );

        if (any { $_ eq $updated_agent } @valid) {
            return $updated_agent;
        }
        else {
            croak 'invalid agent: "' . $agent . '"';
        }
    }
);

sub _convert_deprecated_agent {
    my ($agent) = @_;

    my %deprecated = (
        iphone => 'iphone4',
        ipad_seven => 'ipad',
        android_phone => 'nexus4',
        android_tablet => 'nexus10'
    );

    if ( exists $deprecated{ $agent }) {
        # Attempt to return the updated agent key as of v0.06 that will be able to
        # pass the coercion
        return $deprecated{ $agent };
    }
    else {
        return $agent;
    }
}

=attr orientation

Optional: specify the orientation of the mobile device. Your options
are C<portrait> or C<landscape>; defaults to C<portrait>.

=cut

has orientation => (
    is => 'rw',
    coerce => sub {
        croak 'Invalid orientation; please choose "portrait" or "landscape'
          unless $_[0] =~ /portrait|landscape/;
        return $_[0];
    },
    default => 'portrait'
);

has _firefox_options => (
    is => 'ro',
    lazy => 1,
    builder => sub {
        my ($self) = @_;

        my $dim = $self->_get_size;

        my $profile = Selenium::Firefox::Profile->new;
        $profile->set_preference(
            'general.useragent.override' => $self->_get_user_agent
        );

        return {
            firefox_profile => $profile
        };
    }
);

has _chrome_options => (
    is => 'ro',
    lazy => 1,
    builder => sub {
        my ($self) = @_;

        my $size = $self->_get_size;
        my $window_size = $size->{width} . ',' . $size->{height};

        return {
            chromeOptions => {
                args => [
                    'user-agent=' . $self->_get_user_agent,
                ],
                mobileEmulation => {
                    deviceMetrics => {
                        width => $size->{width} + 0,
                        height => $size->{height} + 0,
                        pixelRatio => $size->{pixel_ratio}
                    },
                    userAgent => $self->_get_user_agent
                }
            }
        }
    }
);

has _specs => (
    is => 'ro',
    builder => sub {
        my $devices_file = abs_path(__FILE__);
        $devices_file =~ s/UserAgent\.pm$/devices.json/;

        my $devices;
        {
            local $/ = undef;
            open (my $fh, "<", $devices_file);
            $devices = from_json(<$fh>);
            close ($fh);
        }

        return $devices;
    }
);

=method caps

Call this after initiating the ::UserAgent object to get the
capabilities that you should pass to
L<Selenium::Remote::Driver/new_from_caps>. This function returns a
hashref with the following keys:

=over 4

=item inner_window_size

This will set the window size immediately after browser creation.

=item desired_capabilities

This will set the browserName and the appropriate options needed.

=back

If you're using Firefox and you'd like to continue editing the Firefox
profile before passing it to the Driver, pass in C<< unencoded => 1 >>
as the argument to this function.

=cut

sub caps {
    my ($self, %args) = @_;

    my $options = $self->_desired_options(%args);

    return {
        inner_window_size => $self->_get_size_for('caps'),
        desired_capabilities => {
            browserName => $self->browserName,
            %$options
        }
    };
}

sub _desired_options {
    my ($self, %args) = @_;

    my $options;
    if ($self->_is_chrome) {
        $options = $self->_chrome_options;
    }
    elsif ($self->_is_firefox) {
        $options = $self->_firefox_options;

        unless (%args && exists $args{unencoded} && $args{unencoded}) {
            $options->{firefox_profile} = $options->{firefox_profile}->_encode;
        }
    }

    return $options;
}

sub _get_user_agent {
    my ($self) = @_;

    my $specs = $self->_specs;
    my $agent = $self->agent;

    return $specs->{$agent}->{user_agent};
}

sub _get_size {
    my ($self) = @_;

    my $specs = $self->_specs;
    my $agent = $self->agent;
    my $orientation = $self->orientation;

    my $size = $specs->{$agent}->{$orientation};
    $size->{pixel_ratio} = $specs->{$agent}->{pixel_ratio};

    return $size;
}

sub _get_size_for {
    my ($self, $format) = @_;
    my $dim = $self->_get_size;

    if ($format eq 'caps') {
        return [ $dim->{height}, $dim->{width} ];
    }
    elsif ($format eq 'chrome') {
        return $dim->{width} . ',' . $dim->{height};
    }
}

sub _is_firefox {
    return shift->browserName =~ /firefox/i
}

sub _is_chrome {
    return shift->browserName =~ /chrome/i
}

1;

=head1 SEE ALSO

Selenium::Remote::Driver
Selenium::Firefox::Profile
https://github.com/alisterscott/webdriver-user-agent

=cut
