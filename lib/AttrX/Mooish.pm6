unit module AttrX::Mooish:ver<0.7.902>:auth<github:vrurg>;
#use Data::Dump;
use nqp;

=begin pod
=head1 NAME

C<AttrX::Mooish> - extend attributes with ideas from Moo/Moose (laziness!)

=head1 SYNOPSIS

    use AttrX::Mooish;
    class Foo {
        has $.bar1 is mooish(:lazy, :clearer, :predicate) is rw;
        has $!bar2 is mooish(:lazy, :clearer, :predicate, :trigger);
        has Num $.bar3 is rw is mooish(:lazy, :filter);

        method build-bar1 {
            "lazy init value"
        }

        method !build-bar2 {
            "this is private mana!"
        }

        method !trigger-bar2 ( $value ) {
            # do something after attribute changed.
        }

        method build-bar3 {
            rand;
        }

        method filter-bar3 ( $value, *%params ) {
            if %params<old-value>:exists {
                # Only allow the value to grow
                return ( !%params<old-value>.defined || $value > %params<old-value> ) ?? $value !! %params<old-value>;
            }
            # Only allow inital values from 0.5 and higher
            return $value < 0.5 ?? Nil !! $value;
        }

        method baz {
            # Yes, works with private too! Isn't it magical? ;)
            "Take a look at the magic: «{ $!bar2 }»";
        }
    }

    my $foo = Foo.new;

    say $foo.bar1;
    say $foo.bar3.defined ?? "DEF" !! "UNDEF";
    for 1..10 { $foo.bar3 = rand; say $foo.bar3 }

The above would generate a output similar to the following:

    lazy init value
    UNDEF
    0.08662089602505263
    0.49049512098324255
    0.49049512098324255
    0.5983833081770437
    0.9367804461546302
    0.9367804461546302
    0.9367804461546302
    0.9367804461546302
    0.9367804461546302
    0.9367804461546302

=head1 DESCRIPTION

This module is aiming at providing some functionality we're all missing from Moo/Moose. It implements laziness,
accompanying methods and adds attribute value filter on top of what standard Moo/Moose provide.

What makes this module different from previous versions one could find in the Raku modules repository is that it
implements true laziness allowing I<Nil> to be a first-class value of a lazy attribute. In other words, if you look at
the L<#SYNOPSIS> section, C<$.bar3> value could randomly be either undefined or 3.1415926.

=head2 Laziness for beginners

This section is inteded for beginners and could be skipped by experienced lazybones.

=head3 What is "lazy attribute"

As always, more information could be found by Google. In few simple words: a lazy attribute is the one which gets its
first value on demand, i.e. – on first read operation. Consider the following code:

    class Foo {
        has $.bar is mooish(:lazy, :predicate);

        method build-bar { π }
    }

    my $foo = Foo.new
    say $foo.has-bar; # False
    say $foo.bar;     # 3.1415926...
    say $foo.has-bar; # True

=head3 When is it useful?

Laziness becomes very handy in cases where intializing an attribute is very expensive operation yet it is not certain
if attribute is gonna be used later or not. For example, imagine a monitoring code which raises an alert when a failure
is detected:

    class Monitor {
        has $.notifier;
        has $!failed-object;

        submethod BUILD {
            $!notifier = Notifier.new;
        }

        method report-failure {
            $.notifier.alert( :$!failed-object );
        }

        ...
    }

Now, imagine that notifier is a memory-consuming object, which is capable of sending notification over different kinds
of media (SMTP, SMS, messengers, etc...). Besides, preparing handlers for all those media takes time. Yet, failures are
rare and we may need the object, say, once in 10000 times. So, here is the solution:

    class Monitor {
        has $.notifier is mooish(:lazy);
        has $!failed-object;

        method build-notifier { Notifier.new( :$!failed-object ) }

        method report-failure {
            $.notifier.alert;
        }

        ...
    }

Now, it would only be created when we really need it.

Such approach also works well in interactive code where many wuch objects are created only the moment a user action
requires them. This way overall responsiveness of a program could be significally incresed so that instead of waiting
long once a user would experience many short delays which sometimes are even hard to impossible to be aware of.

Laziness has another interesting application in the area of taking care of attribute dependency. Say, C<$.bar1> value
depend on C<$.bar2>, which, in turn, depends either on C<$.bar3> or C<$.bar4>. In this case instead of manually defining
the order of initialization in a C<BUILD> submethod, we just have the following code in our attribute builders:

    method build-bar2 {
        if $some-condition {
            return self.prepare( $.bar3 );
        }
        self.prepare( $.bar4 );
    }

This module would take care of the rest.

=head1 USAGE

The L<#SYNOPSIS> is a very good example of how to use the trait C<mooish>.

=head2 Trait parameters

=begin item
I<C<lazy>>

C<Bool>, defines wether attribute is lazy. Can have C<Bool>, C<Str>, or C<Callable> value. The later two have the
same meaning, as for I<C<builder>> parameter.
=end item

=begin item
I<C<builder>>

Defines builder method for a lazy attribute. The value returned by the method will be used to initialize the attribute.

This parameter can have C<Str> or C<Callable> values or be not defined at all. In the latter case we expect a method
with a name composed of "I<build->" prefix followed by attribute name to be defined in our class. For example, for a
attribute named C<$!bar> the method name is expected to be I<build-bar>.

A string value defines builder's method name.

A callable value is used as-is and invoked as an object method. For example:

    class Foo {
        has $.bar is mooish(:lazy, :builder( -> $,*% {"in-place"} );
    }

    $inst = Foo.new;
    say $inst.bar;

This would output 'I<in-place>'.

*Note* the use of slurpy C<*%> in the pointy block. Read about callback parameters below.
=end item

=begin item
I<C<predicate>>

Could be C<Bool> or C<Str>. When defined trait will add a method to determine if attribute is set or not. Note that
it doesn't matter wether it was set with a builder or by an assignment.

If parameter is C<Bool> I<True> then method name is made of attribute name prefixed with U<has->. See
L<#What is "lazy attribute"> section for example.

If parameter is C<Str> then the string contains predicate method name:

=begin code
        has $.bar is mooish(:lazy, :predicate<bar-is-ready>);
        ...
        method baz {
            if self.bar-is-ready {
                ...
            }
        }
=end code
=end item

=begin item
I<C<clearer>>

Could be C<Bool> or C<Str>. When defined trait will add a method to reset the attribute to uninitialzed state. This is
not equivalent to I<undefined> because, as was stated above, I<Nil> is a valid value of initialized attribute.

Similarly to I<C<predicate>>, when I<True> the method name is formed with U<clear-> prefix followed by attribute's name.
A C<Str> value defines method name:

=begin code
        has $.bar is mooish(:lazy, :clearer<reset-bar>, :predicate);
        ...
        method baz {
            $.bar = "a value";
            say self.has-bar;  # True
            self.reset-bar;
            say self.has-bar;  # False
        }
=end code
=end item

=begin item
I<C<filter>>

A filter is a method which is executed right before storing a value to an attribute. What is returned by the method
will actually be stored into the attribute. This allows us to manipulate with a user-supplied value in any necessary
way.

The parameter can have values of C<Bool>, C<Str>, C<Callable>. All values are treated similarly to the C<builder>
parameter except that prefix 'I<filter->' is used when value is I<True>.

The filter method is passed with user-supplied value and two named parameters: C<attribute> with full attribute name;
and optional C<old-value> which could omitted if attribute has not been initialized yet. Otherwise C<old-value> contains
attribute value before the assignment.

B<Note> that it is not recommended for a filter method to use the corresponding attribute directly as it may cause
unforseen side-effects like deep recursion. The C<old-value> parameter is the right way to do it.
=end item

=begin item
I<C<trigger>>

A trigger is a method which is executed when a value is being written into an attribute. It gets passed with the stored
value as first positional parameter and named parameter C<attribute> with full attribute name. Allowed values for this
parameter are C<Bool>, C<Str>, C<Callable>. All values are treated similarly to the C<builder> parameter except that
prefix 'I<trigger->' is used when value is I<True>.

Trigger method is being executed right after changing the attribute value. If there is a C<filter> defined for the
attribute then value will be the filtered one, not the initial.
=end item

=begin item
I<C<alias>, C<aliases>, C<init-arg>, C<init-args>>

Those are four different names for the same parameter which allows defining attribute aliases. So, whereas Internally
you would have single container for an attribute that container would be accessible via different names. And it means
not only attribute accessors but also clearer and predicate methods:

    class Foo {
        has $.bar is rw is mooish(:clearer, :lazy, :aliases<fubar baz>);

        method build-bar { "The Answer" }
    }

    my $inst = Foo.new( fubar => 42 );
    say $inst.bar; # 42
    $inst.clear-baz;
    say $inst.bar; # The Answer
    $inst.fubar = pi;
    say $inst.baz; # 3.1415926

Aliases are not applicable to methods called by the module like builders, triggers, etc.
=end item

=begin item
I<C<no-init>>

This parameter will prevent the attribute from being initialized by the constructor:


    class Foo {
        has $.bar is mooish(:lazy, :no-init);

        method build-bar { 42 }
    }

    my $inst = Foo.new( bar => "wrong answer" );
    note $inst.bar; # 42
=end item

=begin item
I<C<composer>>

This is a very specific option mostly useful until role C<COMPOSE> phaser is implemented. Method of this option is
called upon class composition time.
=end item

=head2 Public/Private

For all the trait parameters, if it is applied to a private attribute then all auto-generated methods will be private
too.

The call-back style options such as C<builder>, C<trigger>, C<filter> are expected to share the privace mode of their
respective attribute:

=begin code
    class Foo {
        has $!bar is rw is mooish(:lazy, :clearer<reset-bar>, :predicate, :filter<wrap-filter>);

        method !build-bar { "a private value" }
        method baz {
            if self!has-bar {
                self!reset-bar;
            }
        }
        method !wrap-filter ( $value, :$attribute ) {
            "filtered $attribute: ($value)"
        }
    }
=end code

Though if a callback option is defined with method name instead of C<Bool> I<True> then if method wit the same privacy
mode is not found then opposite mode would be tried before failing:

=begin code
    class Foo {
        has $.bar is mooish( :trigger<on_change> );
        has $!baz is mooish( :trigger<on_change> );
        has $!fubar is mooish( :lazy<set-fubar> );

        method !on_change ( $val ) { say "changed! ({$val})"; }
        method set-baz { $!baz = "new pvt" }
        method use-fubar { $!fubar }
    }

    $inst = Foo.new;
    $inst.bar = "new";  # changed! (new)
    $inst.set-baz;      # changed! (new pvt)
    $inst.use-fubar;    # Dies with "No such private method '!set-fubar' for invocant of type 'Foo'" message
=end code

=head2 User method's (callbacks) options

User defined (callback-type) methods receive additional named parameters (options) to help them understand their
context. For example, a class might have a couple of attributes for which it's ok to have same trigger method if only it
knows what attribute it is applied to:

=begin code
    class Foo {
        has $.foo is rw is mooish(:trigger('on_fubar'));
        has $.bar is rw is mooish(:trigger('on_fubar'));

        method on_fubar ( $value, *%opt ) {
            say "Triggered for {%opt<attribute>} with {$value}";
        }
    }

    my $inst = Foo.new;
    $inst.foo = "ABC";
    $inst.bar = "123";
=end code

    The expected output would be:

=begin code
    Triggered for $!foo with with ABC
    Triggered for $!bar with with 123
=end code

B<NOTE:> If a method doesn't care about named parameters it may only have positional arguments in its signature. This
doesn't work for pointy blocks where anonymous slurpy hash would be required:

=begin code
    class Foo {
        has $.bar is rw is mooish(:trigger(-> $, $val, *% {...}));
    }
=end code

=head3 Options

=begin item
I<C<attribute>>

Full attribute name with twigil. Passed to all callbacks.
=end item

=begin item
I<C<builder>>

Only set to I<True> for C<filter> and C<trigger> methods when attribute value is generated by lazy builder. Otherwise no
this parameter is not passed to the method.
=end item

=begin item
I<C<old-value>>

Set for C<filter> only. See its description above.
=end item

=head2 Some magic

Note that use of this trait doesn't change attribute accessors. More than that, accessors are not required for private
attributes. Consider the C<$!bar2> attribute from L<#SYNOPSIS>.

=head2 Performance

Module versions prior to v0.5.0 were pretty much costly perfomance-wise. This was happening due to use of C<Proxy> to
handle all attribute read/writes. Since v0.5.0 only the first read/write operation would be handled by this module
unless  C<filter> or C<trigger> parameters are used. When C<AttrX::Mooish> is assured that the attribute is properly
initialized it steps aside and lets the Raku core to do its job without intervention.

The only exception takes place if C<clearer> parameter is used and C«clear-<attribute>» method is called. In this case
the attribute state is reverted back to uninitialized state and C<Proxy> is getting installed again – until the next
read/write operation.

C<filter> and C<trigger> are exceptional here because they require permanent monitoring of attribute operations making
it effectively impossible to drop C<Proxy>. For this reason use of these parameters must be very carefully considered
and highly discouraged for any code where performance is of the high precedence.

=head1 CAVEATS

Due to the magical nature of attribute behaviour conflicts with other traits are possible. None is known to the author
yet.

Internally C<Proxy> is used as attribute container. It was told that the class has a number of unpleasant side effects
including multiplication of FETCH operation. Though generally this bug is harmles it could be workarounded by assigning
an attribute value to a temporary variable.

=head1 AUTHOR

Vadim Belman <vrurg@cpan.org>

=head1 LICENSE

Artistic License 2.0

See the LICENSE file in this distribution.

=end pod

CHECK {
    die "Rakudo of at least v2019.11 required to run this version of " ~ ::?PACKAGE.^name
        unless $*PERL.compiler.version >= v2019.11;
}

class X::Fatal is Exception {
    #has Str $.message is rw;
}

class X::TypeCheck::MooishOption is X::TypeCheck {
    method expectedn {
        "Str or Callable";
    }
}

my class AttrProxy is Proxy {
    has $.val is rw;
    has Bool $.is-set is rw is default(False);
    has Promise $!built-promise;
    has Bool $.mooished is rw is default(False);

    method clear {
        $!val = Nil;
        $!is-set = Nil;
        $!built-promise = Nil;
    }

    method build-acquire {
        return False if $!is-set;
        my $bp = $!built-promise;
        if !$bp.defined && cas($!built-promise, $bp, Promise.new) === $bp {
            # note "ACQUIRED, promise: ", $!built-promise.WHICH if $*AXM-DEBUG;
            return True;
        }
        await $!built-promise;
        False
    }

    method build-release {
        $!built-promise.keep(True);
    }

    method assign-val( $value is raw ) {
        nqp::p6assign($!val, $value);
        $!is-set = True;
    }
    method bind-val( $value is raw ) {
        nqp::bindattr(self, AttrProxy, '$!val', $value);
        # $!val := $value;
        $!is-set = True;
    }
}

# PvtMode enum defines what privacy mode is used when looking for an option method:
# force: makes the method always private
# never: makes it always public
# as-attr: makes is strictly same as attribute privacy
# auto: when options is defined with method name string then uses attribute mode first; and uses opposite if not
#       found. Always uses attribute mode if defined as Bool
enum PvtMode <pvmForce pvmNever pvmAsAttr pvmAuto>;

role AttrXMooishClassHOW { ... }

role AttrXMooishHelper {
    method setup-helpers ( Mu \type, $attr ) is hidden-from-backtrace {
        # note "SETUP HELPERS ON ", type.^name, " // ", type.HOW.^name;
        # note " .. for attr ", $attr.name;
        my sub get-attr-obj( Mu \obj, $attr ) is raw is hidden-from-backtrace {
            $attr.package.HOW ~~ Metamodel::GenericHOW
                ?? (
                    ( try { obj.^get_attribute_for_usage($attr.name) } )
                    || obj.^attributes.grep({ $_.name eq $attr.name }).first
                )
                !! $attr;
        }
        my %helpers =
            :clearer( my method {
                # Can't use $attr to call bind-proxy upon if the original attribute belongs to a role. In this case its
                # .package is not defined.
                # Metamodel::GenericHOW only happens for role attributes
                my $attr-obj = get-attr-obj(self, $attr);
                my $attr-var := $attr-obj.bind-proxy( self, nqp::getattr(self, $attr-obj.package, $attr.name).VAR );
                $attr-obj.clear-attr( self );
                $attr-var.mooished = True;
             } ),
            :predicate( my method   { get-attr-obj(self, $attr).is-set( self ) } ),
            ;

        my @aliases = $attr.base-name, |$attr.init-args;

        for %helpers.keys -> $helper {
            next unless $attr."$helper"(); # Don't generate if attribute isn't set
            #note "op2method for helper $helper";
            for @aliases -> $base-name {
                my $helper-name = $attr.opt2method( $helper, :$base-name  );

                X::Fatal.new( message => "Cannot install {$helper} {$helper-name}: method already defined").throw
                    if type.^declares_method( $helper-name );

                my $m = %helpers{$helper};
                $m.set_name( $helper-name );
                #note "Installing helper $helper $helper-name on {type.^name} // {$m.WHICH}";
                #note "HELPER:", %helpers{$helper}.name, " // ", $m.^can("CALL-ME"), " // ", $m.^name;

                if $attr.has_accessor { # I.e. – public?
                    #note ". Installing public $helper-name";
                    type.^add_method( $helper-name, $m );
                } else {
                    #note "! Installing private $helper-name";
                    type.^add_private_method( $helper-name, $m );
                }
            }
        }
    }
}

my sub typecheck-attr-value ( $attr is raw, $value ) is raw is hidden-from-backtrace {
    my $rc;
    given $attr.name.substr(0,1) {      # Take sigil from attribute name
        when '$' {
            # Do it via nqp because I didn't find any syntax-based way to properly clone a Scalar container
            # as such.
            my $v := nqp::create(Scalar);
            nqp::bindattr($v, Scalar, '$!descriptor',
                nqp::getattr(nqp::decont($attr), Attribute, '$!container_descriptor')
            );
            # note "SCALAR OF ", $v.VAR.of;
            $rc := $v = $value;
        }
        when '@' {
            #note "ASSIGN TO POSITIONAL";
            my @a := $attr.auto_viv_container.clone;
            #note $value.perl;
            $rc := @a = |$value;
        }
        when '%' {
            my %h := $attr.auto_viv_container.clone;
            $rc := %h = $value;
        }
        when '&' {
            my &m := nqp::clone($attr.auto_viv_container.VAR);
            $rc := &m = $value;
        }
        default {
            die "AttrX::Mooish can't handle «$_» sigil";
        }
    }
    # note "=== RC: ", $rc.VAR.^name, " // ", $rc.VAR.of;
    $rc
}

role AttrXMooishAttributeHOW {
    has $.base-name = self.name.substr(2);
    has $!sigil = self.name.substr( 0, 1 );
    has $!always-bind = False;
    has $.lazy is rw = False;
    has $.builder is rw = 'build-' ~ $!base-name;
    has $.clearer is rw = False;
    has $.predicate is rw = False;
    has $.trigger is rw = False;
    has $.filter is rw = False;
    has $.composer is rw = False;
    has $.no-init is rw = False;
    has @.init-args;
    has Promise $!built-promise;

    my %opt2prefix = clearer => 'clear',
                     predicate => 'has',
                     builder => 'build',
                     trigger => 'trigger',
                     filter => 'filter',
                     composer => 'compose',
                     ;

    method !bool-str-meth-name( $opt, Str $prefix, Str :$base-name? ) is hidden-from-backtrace {
        #note "bool-str-meth-name: ", $prefix;
        $opt ~~ Bool ?? $prefix ~ '-' ~ ( $base-name // $!base-name ) !! $opt;
    }

    method opt2method( Str $oname, Str :$base-name? ) is hidden-from-backtrace {
        #note "%opt2prefix: ", %opt2prefix;
        #note "option name in opt2method: $oname // ", %opt2prefix{$oname};
        self!bool-str-meth-name( self."$oname"(), %opt2prefix{$oname}, :$base-name );
    }

    method compose ( Mu \type, :$compiler_services ) is hidden-from-backtrace {
        # note "+++ composing {$.name} on {type.^name} {type.HOW}, was composed? ", $composed;
        # $!composed is a recent addition on Attribute object.
        return if try nqp::getattr_i(self, Attribute, '$!composed');

        # note "ATTR PACKAGE:", $.package.^name;

        $!always-bind = $!filter || $!trigger;

        unless type.HOW ~~ AttrXMooishClassHOW {
            #note "Installing AttrXMooishClassHOW on {type.WHICH}";
            type.HOW does AttrXMooishClassHOW;
        }

        for @!init-args -> $alias {
            # note "GEN ACCESSOR $alias for {$.name} on {type.^name}";
            my $meth := $compiler_services.generate_accessor(
                $alias, nqp::decont(type), $.name, nqp::decont( $.type ), $.rw ?? 1 !! 0
            );
            type.^add_method( $alias, $meth );
        }

        callsame;

        self.invoke-composer( type );

        #note "+++ done composing attribute {$.name}";
    }

    method make-mooish ( Mu \instance, %attrinit ) is hidden-from-backtrace {
        my $attr = self;
        my Mu $attr-var := nqp::getattr(nqp::decont(instance), $.package, $.name).VAR;

        return if nqp::istype($attr-var, AttrProxy);

        # note ">>> HAS INIT: ", %attrinit;

        my $init-key = $.no-init ?? Nil !! ($!base-name, |@!init-args).grep( { %attrinit{$_}:exists } ).head;
        # note "=== Taking $!base-name from init? ", ? $init-key;
        my $initialized = ? $init-key;
        my $default = $initialized ?? %attrinit{$init-key} !! self.get_value( instance );
        # note "DEFAULT IS:", $default // $default.WHAT;
        unless $initialized { # False means no constructor parameter for the attribute
            # note ". No $.name constructor parameter on $obj-id, checking default {$default // '(Nil)'}";
            given $default {
                when Array | Hash { $initialized = so .elems; }
                default { $initialized = nqp::isconcrete(nqp::decont($_)) }
            }
        }

        # note "ATTR-VAR BEFORE BIND: ", $attr-var.^name;
        $attr-var := self.bind-proxy( instance, $attr-var );
        # note "ATTR-VAR AFTER BIND: ", $attr-var.^name;

        if $initialized {
            # note "=== Using initial value (initialized:{$initialized}) ", $default;
            my @params;
            @params.append( {:constructor} ) if $init-key;
            # note "INIT STORE PARAMS: {@params}";
            self.store-with-cb( instance, $attr-var, $default, @params );
        }

        # note "Setting mooished";
        $attr-var.mooished = True;
        # note "<<< DONE MOOIFYING ", $.name;
    }

    method bind-proxy ( Mu \instance, Mu $attr-var is raw ) is raw is hidden-from-backtrace {
        my $attr = self;
        return $attr-var if nqp::istype($attr-var, AttrProxy);

        # note "++++ BINDING PROXY TO ", $.name;

        my $proxy;
        nqp::bindattr(nqp::decont(instance), $.package, $.name,
            $proxy := AttrProxy.new(
                FETCH => -> $ {
                    #note "FETCHING";
                    my Mu $attr-var := $proxy.VAR;
                    my $val;
                    # note "ATTR<{$.name}> SIGIL: ", $!sigil, ", attr-var:", $attr-var.^name, " prox: ", $proxy.VAR.^name;
                    # note "SELF:", self.^name, ", auto viv: ", nqp::getattr(self, Attribute, '$!auto_viv_container').^name, ", generic? ", self.auto_viv_container.HOW.archetypes.generic;
                    if $!sigil eq '$' | '&' {
                        $val := nqp::clone(self.auto_viv_container.VAR);
                    }
                    else {
                        $val := self.auto_viv_container.clone;
                    }
                    # note "IS MOOISHED? ", ? nqp::istype($attr-var, AttrProxy) && $attr-var.mooished if $*AXM-DEBUG;
                    if nqp::istype($attr-var, AttrProxy) && $attr-var.mooished {
                        # note "FETCH of {$attr.name}, lazy? ", ?$!lazy, ", set? ", $attr-var.is-set if $*AXM-DEBUG;
                        if ?$!lazy && $attr-var.build-acquire {
                            LEAVE $attr-var.build-release;
                            # note "BUILDING {$attr.name} for {instance.WHICH} attr var: ", $attr-var.^name, "|", nqp::objectid($attr-var) if $*AXM-DEBUG;
                            self.build-attr( instance, $attr-var );
                        }
                        $val := $attr-var.val if $attr-var.is-set;
                        # note "Fetched value for {$.name}: ", $val.VAR.^name, " // ", $val.perl, "; attr was set? ", $attr-var.is-set;
                        # Once read and built, mooishing is not needed unless filter or trigger are set; and until
                        # clearer is called.
                        self.unbind-proxy( instance, $attr-var, $val );
                    }
                    $val
                },
                STORE => -> $, $value is copy {
                    self.store-with-cb( instance, $proxy.VAR, $value );
                }
            )
        );
        $proxy.VAR
    }

    method unbind-proxy ( Mu \instance, $attr-var is raw, $val is raw ) {
        unless $!always-bind or $attr-var !~~ AttrProxy {
            # note "---- UNBINDING ATTR {$.name} FROM {$attr-var.^name} INTO VALUE ({$val.^name}";
            nqp::bindattr( nqp::decont(instance), $.package, $.name, $val );
        }
    }

    method store-with-cb ( Mu \instance, $attr-var is raw, $value is rw, @params = () ) is hidden-from-backtrace {
        # note "INVOKING {$.name} FILTER WITH {@params.perl}";
        self.invoke-filter( instance, $attr-var, $value, @params ) if $!filter;
        # note "STORING VALUE: ($value) on ", ;
        self.store-value( instance, $attr-var, $value );
        #note "INVOKING {$.name} TRIGGER WITH {@params.perl}";
        self.invoke-opt( instance, 'trigger', ( $value, |@params ), :strict ) if $!trigger;
    }

    # store-value would return the value stored.
    method store-value ( Mu \instance, $attr-var is raw, $value is copy ) is hidden-from-backtrace {
        # note ". storing into {$.name} // ";
        # note "store-value($value) on attr({$.name}) of ", $attr-var.^name;

        if $attr-var.is-set {
                # note " . was set";
                given $!sigil {
                    when '$' | '&' {
                            $attr-var.assign-val( $value );
                    }
                    when '@' | '%' {
                        $attr-var.val.STORE(nqp::decont($value));
                    }
                    default {
                        die "AttrX::Mooish can't handle «$_» sigil";
                    }
                }
        }
        else {
            # note " . binding new value";
            $attr-var.bind-val( typecheck-attr-value( self, $value ) );
            # note " . -> ", $attr-var.val;
        }

        self.unbind-proxy( instance, $attr-var, $attr-var.val );
    }

    method is-set ( Mu \obj ) is hidden-from-backtrace {
        my $attr-var := nqp::getattr(nqp::decont(obj), $.package, $.name).VAR;
        # note ". IS-SET on {$.name} of {$attr-var.^name}: ", (nqp::istype($attr-var, AttrProxy) ?? $attr-var.is-set !! "not proxy");
        !nqp::istype($attr-var, AttrProxy) || $attr-var.is-set
    }

    method clear-attr ( Mu \obj ) is hidden-from-backtrace {
        my $attr-var := nqp::getattr(nqp::decont(obj), $.package, $.name).VAR;
        # note "Clearing {$.name} on ", $attr-var.^name;
        $!built-promise = Nil;
        $attr-var.clear if nqp::istype($attr-var, AttrProxy);
    }

    method invoke-filter ( Mu \instance, $attr-var is raw, $value is rw, @params = () ) is hidden-from-backtrace {
        if $!filter {
            my @invoke-params = $value, |@params;
            @invoke-params.push( 'old-value' => $attr-var.val ) if $attr-var.is-set;
            $value = self.invoke-opt( instance, 'filter', @invoke-params, :strict );
        }
    }

    method invoke-opt (
                Any \instance, Str $option, @params = (), :$strict = False, PvtMode :$private is copy = pvmAuto
            ) is hidden-from-backtrace {
        my $opt-value = self."$option"();
        my \type = $.package;

        return unless so $opt-value;

        # note "&&& INVOKING {$option} on {$.name}";

        my @invoke-params = :attribute($.name), |@params;

        my $method;

        sub get-method( $name, Bool $public ) {
            $public ??
                    instance.^find_method( $name, :no_fallback(1) )
                    !!
                    type.^find_private_method( $name )
        }

        given $opt-value {
            when Str | Bool {
                if $opt-value ~~ Bool {
                    die "Bug encountered: boolean option $option doesn't have a prefix assigned"
                        unless %opt2prefix{$option};
                    $opt-value = "{%opt2prefix{$option}}-{$!base-name}";
                    # Bool-defined option must always have same privacy as attribute
                    $private = pvmAsAttr if $private == pvmAuto;
                }
                my $is-pub = $.has_accessor;
                given $private {
                    when pvmForce | pvmNever {
                        $method = get-method( $opt-value, $is-pub = $_ == pvmNever );
                    }
                    when pvmAsAttr {
                        $method = get-method( $opt-value, $.has_accessor );
                    }
                    when pvmAuto {
                        $method = get-method( $opt-value, $.has_accessor ) // get-method( $opt-value, !$.has_accessor );
                    }
                }
                #note "&&& ON INVOKING: found method ", $method.defined ;
                unless so $method {
                    # If no method found by name die if strict is on
                    #note "No method found for $option";
                    return unless $strict;
                    X::Method::NotFound.new(
                        method => $opt-value,
                        private =>!$is-pub,
                        typename => instance.WHO,
                    ).throw;
                }
            }
            when Callable {
                $method = $opt-value;
            }
            default {
                die "Bug encountered: $option is of unsupported type {$opt-value.WHO}";
            }
        }

        #note "INVOKING {$method ~~ Code ?? $method.name !! $method} with ", @invoke-params.Capture;
        instance.$method(|(@invoke-params.Capture));
    }

    method build-attr ( Any \instance, $attr-var is raw ) is hidden-from-backtrace {
        my $publicity = $.has_accessor ?? "public" !! "private";
        # note "&&& KINDA BUILDING FOR $publicity {$.name} on {$attr-var.^name} (is-set:{$attr-var.is-set})";
        unless $attr-var.is-set {
            # note "&&& Calling builder {$!builder} // ", "set: ", $attr-var.is-set;
            my $val = self.invoke-opt( instance, 'builder', :strict );
            # note "Set ATTR to ({$val})";
            self.store-with-cb( instance, $attr-var, $val, [ :builder ] );
        }
    }

    method invoke-composer ( Mu \type ) is hidden-from-backtrace {
        return unless $!composer;
        #note "My type for composer: ", $.package;
        my $comp-name = self.opt2method( 'composer' );
        # note "Looking for method $comp-name";
        my &composer = type.^find_private_method( $comp-name );
        X::Method::NotFound.new(
            method    => $comp-name,
            private  => True,
            typename => type.WHO,
        ).throw unless &composer;
        type.&composer();
    }
}

role AttrXMooishClassHOW does AttrXMooishHelper {
    has %!init-arg-cache;

    method compose ( Mu \type, :$compiler_services ) is hidden-from-backtrace {
        for type.^attributes.grep( AttrXMooishAttributeHOW ) -> $attr {
            self.setup-helpers( type, $attr );
        }
        # note "+++ done composing {type.^name}";
        nextsame;
    }

    method install-stagers ( Mu \type ) is hidden-from-backtrace {
        # note "+++ INSTALLING STAGERS {type.WHO} {type.HOW}";
        my %wrap-methods;
        my $how = self;

        my $has-build = type.^declares_method( 'BUILD' );
        my $iarg-cache := %!init-arg-cache;
        %wrap-methods<BUILD> = my submethod (*%attrinit) {
            # note "&&& CUSTOM BUILD on {self.WHO} by {type.WHO} // has-build:{$has-build}";
            # Don't pass initial attributes if wrapping user's BUILD - i.e. we don't initialize from constructor
            # note "BUILD ON ", self.WHICH;
            type.^on_create( self, $has-build ?? {} !! %attrinit );

            when !$has-build {
                # We would have to init all non-mooished attributes from attrinit.
                my $base-name;
                # note "ATTRINIT: ", %attrinit;
                for type.^attributes( :local(1) ).grep( {
                    $_ !~~ AttrXMooishAttributeHOW
                    && .has_accessor
                    && (%attrinit{$base-name = .name.substr(2)}:exists)
                } ) -> $lattr {
                    # note "--- INIT PUB ATTR $base-name // ", $lattr.^name;
                    #note "WHO:", $lattr.WHO;
                    # my $val = %attrinit{$base-name};
                    $lattr.set_value( self, typecheck-attr-value( $lattr, %attrinit{$base-name} ) );
                }
            }
            nextsame;
        }

        for %wrap-methods.keys -> $method-name {
            my $orig-method = type.^declares_method( $method-name );
            my $my-method = %wrap-methods{$method-name};
            $my-method.set_name( $method-name );
            if $orig-method {
                # note "&&& WRAPPING $method-name";
                type.^find_method($method-name, :no_fallback(1)).wrap( $my-method );
            }
            else {
                # note "&&& ADDING $method-name on {type.^name}";
                self.add_method( type, $method-name, $my-method );
            }
        }

        type.^setup_finalization;
        #type.^compose_repr;
        #note "+++ done installing stagers";
    }

    method create_BUILDPLAN ( Mu \type ) is hidden-from-backtrace {
        #note "+++ PREPARE {type.WHO}";
        self.install-stagers( type );
        callsame;
        #note "+++ done create_BUILDPLAN";
    }

    method on_create ( Mu \type, Mu \instance, %attrinit ) is hidden-from-backtrace {
        # note "ON CREATE, self: ", self.WHICH;

        state $init-lock = Lock.new;

        my @lazyAttrs = type.^attributes( :local(1) ).grep( AttrXMooishAttributeHOW );

        $init-lock.protect: {
            for @lazyAttrs -> $attr {
                # note "Found lazy attr {$attr.name} // {$attr.HOW} // ", $attr.init-args, " --> ", $attr.init-args.elems;
                next unless %!init-arg-cache{ $attr.name }:exists;
                %!init-arg-cache{ $attr.name } = $attr if $attr.init-args.elems > 0;
            }
        }

        for @lazyAttrs -> $attr {
            $attr.make-mooish( instance, %attrinit );
        }
    }
}

role AttrXMooishRoleHOW does AttrXMooishHelper {
    method compose (Mu \type, :$compiler_services ) is hidden-from-backtrace {
        # note "COMPOSING ROLE ", type.^name, " // ", type.HOW.^name, " // ", ? $compiler_services;
        for type.^attributes.grep( AttrXMooishAttributeHOW ) -> $attr {
            self.setup-helpers( type, $attr );
        }
        # note "+++ done composing {type.^name}";
        nextsame
    }

    method specialize(Mu \r, Mu:U \obj, *@pos_args, *%named_args) is hidden-from-backtrace {
        # note "*** Specializing role {r.^name} on {obj.WHO}";
        #note "CLASS HAS THE ROLE:", obj.HOW ~~ AttrXMooishClassHOW;
        obj.HOW does AttrXMooishClassHOW unless obj.HOW ~~ AttrXMooishClassHOW;
        #note "*** Done specializing";
        nextsame;
    }
}

multi trait_mod:<is>( Attribute:D $attr, :$mooish! ) is export {
    $attr does AttrXMooishAttributeHOW;
    # note "Applying for {$attr.name} to ", $*PACKAGE.WHO, " // ", $*PACKAGE.HOW;
    #$*PACKAGE.HOW does AttrXMooishClassHOW unless $*PACKAGE.HOW ~~ AttrXMooishClassHOW;
    given $*PACKAGE.HOW {
        when Metamodel::ParametricRoleHOW {
            $_ does AttrXMooishRoleHOW unless $_ ~~ AttrXMooishRoleHOW;
        }
        default {
            $_ does AttrXMooishClassHOW unless $_ ~~ AttrXMooishClassHOW;
        }
    }

    my $opt-list;

    given $mooish {
        when Bool { $opt-list = (); }
        when List { $opt-list = $mooish; }
        when Pair { $opt-list = [ $mooish ] }
        default { die "Unsupported mooish value type {$mooish.WHO}" }
    }

    for $opt-list.values -> $option {

        sub set-callable-opt ($opt, :$opt-name?) {
            my $option = $opt-name // $opt.key;
            X::TypeCheck::MooishOption.new(
                operation => "set option {$opt.key} of mooish trait",
                got => $opt.value,
                expected => Str,
            ).throw unless $opt.value ~~ Str | Callable;
            $attr."$option"() = $opt.value;
        }

        given $option {
            when Pair {
                given $option.key {
                    when 'lazy' {
                        $attr.lazy = $option.value;
                        set-callable-opt( opt-name => 'builder', $option ) unless $option.value ~~ Bool;
                    }
                    when 'builder' {
                        set-callable-opt( $option );
                    }
                    when 'trigger' | 'filter' | 'composer' {
                        $attr."$_"() = $option.value;
                        set-callable-opt( $option ) unless $option.value ~~ Bool;
                    }
                    when 'clearer' | 'predicate' {
                        my $opt = $_;

                        given $option{$opt} {
                            X::Fatal.new( message => "Unsupported {$opt} type of {.WHAT} for attribute {$attr.name}; can only be Bool or Str" ).throw
                                unless $_ ~~ Bool | Str;
                            $attr."$opt"() = $_;
                        }
                    }
                    when 'no-init' {
                        $attr.no-init = ? $option.value;
                    }
                    when 'init-arg' | 'alias' | 'init-args' | 'aliases' {
                        given $option{$_} {
                            X::Fatal.new( message => "Unsupported {$_} type of {.WHAT} for attribute {$attr.name}; can only be Str or Positional" ).throw
                                unless $_ ~~ Str | Positional;
                            $attr.init-args.append: $_<>;
                        }
                    }
                    default {
                        X::Fatal.new( message => "Unknown named option {$_}" ).throw;
                    }
                }
            }
            default {
                X::Fatal.new( message => "Unsupported option type {$option.WHO}" ).throw;
            }
        }
    }

    #note "*** Done for {$attr.name} to ", $*PACKAGE.WHO, " // ", $*PACKAGE.HOW;
}

# Copyright (c) 2018, Vadim Belman <vrurg@cpan.org>
#
# Check the LICENSE file for the license

# vim: tw=120 ft=perl6
