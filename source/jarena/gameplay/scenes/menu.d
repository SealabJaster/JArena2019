/// Contains the main menu for the game.
module jarena.gameplay.scenes.menu;

private
{
    import std.typetuple;
    import jarena.core, jarena.gameplay, jarena.graphics, jarena.gameplay.scenes;

    const TEXT_SIZE = 18;
    const TEXT_COLOUR = Colours.rockSalt;
    const BUTTON_SIZE = vec2(80, 40);
    const BUTTON_COLOUR = Colours.azure;
    const MENU_POSITION = vec2(5, 20);
    const MENU_COLOUR = Colours.amazon;
}

@SceneName("Menu")
final class MenuScene : Scene
{
    private
    {
        alias SCENES = TypeTuple!(Test,
                                  DebugMenuScene,
                                  AnimationViewerScene, 
                                  SpriteAtlasViewerScene,
                                  StressTest_Render1Scene);

        StackContainer _list;
    }

    public override
    {
        void onInit()
        {
            this._list = new StackContainer(MENU_POSITION);
            this._list.colour = MENU_COLOUR;
            super.gui.addChild(this._list);

            auto font = Systems.assets.get!Font("Calibri");
            foreach(item; SCENES)
            {
                this._list.addChild(new SimpleTextButton(
                    new Text(font, SceneName.getFrom!item, vec2(), TEXT_SIZE, TEXT_COLOUR),
                    btn => super.manager.swap!item,
                    vec2(0),
                    BUTTON_SIZE,
                    BUTTON_COLOUR
                )).fitToText();
            }
        }

        void onSwap(PostOffice office)
        {
        }

        void onUnswap(PostOffice office)
        {
        }

        void onUpdate(Duration deltaTime, InputManager input)
        {
            super.updateScene(deltaTime);
            super.updateUI(deltaTime);
        }

        void onRender(Window window)
        {
            super.renderScene(window);
            super.renderUI(window);
        }
    }
}
