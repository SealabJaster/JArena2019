module jarena.gameplay.engine;

private
{
    import jarena.core, jarena.graphics, jarena.gameplay;
}

const WINDOW_NAME = "JArena";
const WINDOW_SIZE = uvec2(860, 720);

final class Engine
{
    enum Event : Mail.MailTypeT
    {
        UpdateFPSDisplay = 200
    }

    private
    {
        Window       _window;
        PostOffice   _eventOffice;
        InputManager _input;
        FPS          _fps;
        SceneManager _scenes;
        Timers       _timers;

        MailTimer _temp;
    }

    public
    {
        ///
        void onInit()
        {
            // Setup variables
            this._window        = new Window(WINDOW_NAME, WINDOW_SIZE);
            this._eventOffice   = new PostOffice();
            this._input         = new InputManager(this._eventOffice);
            this._fps           = new FPS();
            this._scenes        = new SceneManager(this._eventOffice, this._input);
            this._timers        = new Timers();

            // Setup init info
            InitInfo.windowSize = this._window.size;

            // Make sure the post office types are valid
            this._eventOffice.reserveTypes!(Window.Event);
            this._eventOffice.reserveTypes!(Engine.Event);

            // Add in other stuff
            import std.stdio : writeln;
            this.events.subscribe(Event.UpdateFPSDisplay, (_, __){ writeln("FPS: ", this._fps.frameCount); });

            debug this.timers.every(GameTime.fromSeconds(1), (){this.events.mailCommand(Event.UpdateFPSDisplay);});
        }

        ///
        void onUpdate()
        {
            import derelict.sfml2.window : sfKeyEscape;

            this._fps.onUpdate();
            this._input.onUpdate();
            this._window.handleEvents(this._eventOffice);

            if(this._input.isKeyDown(sfKeyEscape))
                this._window.close();

            this._window.renderer.clear();
            this._timers.onUpdate(this._fps.elapsedTime);
            this._scenes.onUpdate(this._window, this._fps.elapsedTime);
            this._window.renderer.displayChanges();
        }

        ///
        void doLoop()
        {
            while(this._window.isOpen)
            {
                this.onUpdate();
            }
        }

        ///
        @property @safe @nogc
        inout(Window) window() nothrow inout
        {
            return this._window;
        }

        ///
        @property @safe @nogc
        inout(PostOffice) events() nothrow inout
        {
            return this._eventOffice;
        }

        ///
        @property @safe @nogc
        inout(InputManager) input() nothrow inout
        {
            return this._input;
        }

        ///
        @property @safe @nogc
        inout(SceneManager) scenes() nothrow inout
        {
            return this._scenes;
        }

        ///
        @property @safe @nogc
        inout(Timers) timers() nothrow inout
        {
            return this._timers;
        }
    }
}