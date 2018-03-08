module jarena.gameplay.scenes.menu;

private
{
    import std.typetuple;
    import jarena.core, jarena.gameplay, jarena.graphics, jarena.gameplay.scenes;
}

const TEXT_SIZE = 18;
const TEXT_COLOUR = colour(255, 255, 255, 255);
const MENU_COLOUR = colour(0, 255, 0, 128);
const MENU_POSITION = vec2(5, 20);

@SceneName("Menu")
final class MenuScene : Scene
{
    private
    {
        alias SCENES = TypeTuple!(Test, AnimationViewerScene);

        StackContainer  _list;
    }

    public override
    {
        void onInit()
        {
            this._list = new StackContainer(MENU_POSITION);
            this._list.colour = MENU_COLOUR;

            auto font = super.manager.cache.get!Font("Calibri");
            foreach(item; SCENES)
            {
                this._list.addChild(new SimpleButton(
                    new Text(font, SceneName.getFrom!item, vec2(), TEXT_SIZE, TEXT_COLOUR),
                    btn => super.manager.swap!item
                )).fitToText();
            }
        }

        void onSwap(PostOffice office)
        {
        }

        void onUnswap(PostOffice office)
        {
        }

        void onUpdate(Window window, GameTime deltaTime)
        {
            super.updateScene(window, deltaTime);
            this._list.onUpdate(super.manager.input, deltaTime);

            super.renderScene(window);
            this._list.onRender(window);
        }
    }
}