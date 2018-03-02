///
module jarena.core.time;

private
{
    import derelict.sfml2.system;
}

///
alias TimerFunc = void delegate();

///
struct GameTime
{
    public
    {
        ///
        sfTime handle;

        ///
        @safe
        string toString() nothrow const
        {
            import std.exception : assumeWontThrow;
            import std.format    : format;

            return format("GameTime(%s seconds, %s ms, %s microseconds)", 
                          this.asSeconds, this.asMilliseconds, this.asMicroseconds).assumeWontThrow;
        }

        ///
        static GameTime fromSeconds(float seconds)
        {
            GameTime time;
            time.handle = sfSeconds(seconds);

            return time;
        }

        ///
        static GameTime fromMilliseconds(int ms)
        {
            GameTime time;
            time.handle = sfMilliseconds(ms);

            return time;
        }

        ///
        static GameTime fromMicroseconds(long micro)
        {
            GameTime time;
            time.handle = sfMicroseconds(micro);

            return time;
        }

        ///
        @trusted @nogc
        float asSeconds() nothrow const
        {
            return sfTime_asSeconds(this.handle);
        }

        ///
        @trusted @nogc
        int asMilliseconds() nothrow const
        {
            return sfTime_asMilliseconds(this.handle);
        }

        ///
        @trusted @nogc
        long asMicroseconds() nothrow const
        {
            return sfTime_asMicroseconds(this.handle);
        }
    }
}

///
class Clock
{
    private
    {
        sfClock* _handle;

        @property @safe @nogc
        inout(sfClock*) handle() nothrow inout
        {
            assert(this._handle !is null);
            return this._handle;
        }
    }

    public
    {
        ///
        @trusted @nogc
        this() nothrow
        {
            this._handle = sfClock_create();
        }

        ~this()
        {
            if(this._handle !is null)
                sfClock_destroy(this.handle);
        }

        ///
        @trusted @nogc
        GameTime getElapsedTime() nothrow const
        {
            return GameTime(sfClock_getElapsedTime(this.handle));
        }

        ///
        @trusted @nogc
        GameTime restart() nothrow
        {
            return GameTime(sfClock_restart(this.handle));
        }
    }
}

/++
 + Repeatedly sends a given `Mail` to a PostOffice after a delay.
 +
 + This class is useful for subscribing a certain kind of event to a post office, such as "apply Death to Daniel",
 + and then having that event fire off every 2 seconds, for example.
 + ++/
class MailTimer
{
    import jarena.core.post;

    private
    {
        PostOffice  _office;
        Mail        _mail;
        GameTime    _delay;
        GameTime    _current;
        bool        _isStopped;
    }

    public
    {
        /++
         + Params:
         +  office = The `PostOffice` to send the mail to.
         +  mail   = The `Mail` to send. This mail won't be changed (inside of this class at least) between repeated maililngs.
         +  delay  = A `GameTime` which specifies the delay between each mailing.
         + ++/
        @safe @nogc
        this(PostOffice office, Mail mail, GameTime delay) nothrow pure
        {
            assert(office !is null);
            assert(mail !is null);

            this._office = office;
            this._mail = mail;
            this._delay = delay;
        }

        ///
        void onUpdate(GameTime deltaTime)
        {
            if(this._isStopped)
                return;

            this._current.handle.microseconds += deltaTime.handle.microseconds;
            if(this._current.handle.microseconds >= this._delay.handle.microseconds)
            {
                this._office.mail(this._mail);
                this._current = GameTime();
            }
        }

        ///
        void stop()
        {
            this._isStopped = true;
        }

        ///
        void start()
        {
            this._isStopped = false;
        }

        ///
        void restart()
        {
            this.start();
            this._delay = GameTime();
        }
    }
}

///
class FPS
{
    private
    {
        Clock _clock;
        GameTime _previousFrame;
        float _elapsedSeconds;
        uint _frameCountPrevious;
        uint _frameCount;
    }

    public
    {
        ///
        this()
        {
            this._clock = new Clock();
            this._elapsedSeconds = 0;
        }

        ///
        void onUpdate()
        {
            this._previousFrame = this._clock.restart();
            this._elapsedSeconds += this._previousFrame.asSeconds;

            this._frameCount++;
            if(this._elapsedSeconds >= 1)
            {
                this._frameCountPrevious = this._frameCount;
                this._frameCount = 0;
                this._elapsedSeconds = 0;
            }
        }

        ///
        @property @safe @nogc
        uint frameCount() nothrow const
        {
            return this._frameCountPrevious;
        }

        ///
        @property @safe @nogc
        GameTime elapsedTime() nothrow const
        {
            return this._previousFrame;
        }
    }
}