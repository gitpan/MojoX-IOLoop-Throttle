use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'MojoX::IOLoop::Throttle',
    AUTHOR              => q{Alex <alexbyk@cpan.org>},
    VERSION_FROM        => 'lib/MojoX/IOLoop/Throttle.pm',
    ABSTRACT_FROM       => 'lib/MojoX/IOLoop/Throttle.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
	'Mojolicious' => '2.68',
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'MojoX-IOLoop-Throttle-*' },
);
