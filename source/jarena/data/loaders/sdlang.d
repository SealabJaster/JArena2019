/// Contains a `Loader` and various `Extensions` for SDLang assets.
module jarena.data.loaders.sdlang;

private
{
    import std.experimental.logger, std.exception, std.format;
    import sdlang;
    import jarena.audio, jarena.core, jarena.graphics, jarena.gameplay, jaster.serialise, jarena.data.loaders.core, jarena.maths;
}

/++
 + A `Loader` for SDLang.
 +
 + Notes:
 +  This Loader will automatically register all of the premade extensions that this module contains.
 +
 +  "Animation:list" and "Animation:spriteSheet" are registered under `AnimationExtensionSDL`.
 +
 +  "Sprite:atlas" is registered under `SpriteAtlasExtensionSDL`.
 +
 +  "Font", "Sound", and "Texture" are registered under `NamedFileExtensionSDL`.
 +
 +  See the respective classes for their formats.
 +
 +  Two abstract classes are also provided within the module that contains this class, `LoaderExtensionSDLNamedFile`, and
 +  `LoaderExtensionSDLFile`. Because the 'namedFiles' and 'files' tags provide different data to an excetension (see below, under 'Subtags')
 +  these classes will handle parsing the data given to them ("SDLNamedFile" handles 'namedFile' tags, "SDLFile" handles 'file' tags) and then
 +  providing them to the user-made loading function.
 +
 + Package_Format:
 +  A package file for SDLang is written as such
 +
 +  ```
 +  type "Package"
 +  name "Whatever"
 +
 +  [files {}]
 +  [namedFiles type="someType" {}]
 +  ```
 +
 + There can be any number of 'files' and 'namedFiles' tags.
 +
 + Subtags:
 +  There are 3 other tags that can be used inside the 'files' and 'namedFiles' tags.
 +
 +  'file', which is formatted as `file "Animations/Some_Thing.sdl"' which is used to list an
 +   SDLang file that needs to be loaded in with an extension.
 +
 +  'namedFile', which is formatted as 'namedFile "Background_Music" "Music/Background.mp3"' which is used
 +   to specify a name for a file who's name can't be determined automatically (so any asset that isn't a .sdl file).
 +
 +   Finally, 'glob', which doesn't even work right now so no documentaiton for it.
 +
 + Files_Tag:
 +  A 'files' tag contains a list of 'file', 'namedFile', and 'glob' tags, which all contain a path
 +  to another SDLang file.
 +
 +  $(B Every) SDLang file that this tag lists must contain a 'type' tag, which corresponds directly with
 +  the type an extension is registered with. For example, an SDLang file with the type of 'Sprite:atlas' will
 +  use the extension registered under the same type name.
 +
 +  Here's an example of this section.
 +
 +  ```
 +  type "Package"
 +  name "Example"
 +
 +  files {
 +      file "Animations/Walk.sdl"
 +      glob "Atlases/*.sdl"
 +  }
 +  ```
 +
 +  Note that the 'namedFile' tag functionally acts as a 'file' tag under this section.
 +
 +  When an extension is used to load in a file from the 'files' tag, the 'data' parameter that is passed will be
 +  the contents of the SDLang file. See `Extension.dataToText` for a bit of help with dealing with the parameter.
 +
 + NamedFiles_Tag:
 +  The 'namedFiles' tag contains an attribute called 'type', which specifies which extension
 +  (which was registered under the same type name) to use to load $(B all) of the files specified in the tag.
 +
 +  Note that 'namedFile' is the only subtag that can be used with this section, as there is no other way of determining
 +  a name for these files.
 +
 +  Here is an example of this section.
 +
 +  ```
 +  type "Package"
 +  name "Example"
 +
 +  // All of these files will be loaded using the 'Sound' extension
 +  namedFiles type="Sound" {
 +      namedFile "HitSound" "Sounds/hit.wav"
 +      namedFile "DeathSound" "Sounds/death.wav"
 +  }
 +
 +  // All of these files will be loaded using the 'Texture' extension
 +  namedFiles type="Texture" {
 +      namedFile "CharacterAtlasTexture" "Textures/characters.png"
 +  }
 +  ```
 +
 +  When an extension is used to load a file under the 'namedFiles' tag, then 'data' is sent as a string[] (casted to a ubyte[])
 +  containing three pieces of information. The name, the path, and the type. There is a helper function called `dataToNamedFileData` to make
 +  it easier to deal with this parameter. 
 + ++/
class LoaderSDL : Loader
{
    import std.file      : readText;
    import std.path      : dirName, buildNormalizedPath, isAbsolute, absolutePath;
    import std.algorithm : splitter, map;

    private
    {
        struct NamedFileInfo
        {
            string name;
            string path;
            string type;
            string[string] attributes;
        }

        struct FileInfo
        {
            string path; // Path to the file.
            string name; // Some tags allow you to specify the name to cache the file as.
            string[string] attributes;
        }
        
        // Used to parse 'file' and 'glob' tags, getting any useful data from them.
        FileInfo[] getFileInfo(string baseDir, Tag tag)
        {
            FileInfo[] files;

            // Read in the attributes
            string[string] attribs;
            foreach(attrib; tag.attributes)
                attribs[attrib.name] = attrib.value.get!string;

            // Reminder: All paths must either be absolute, or are assumed to be relative to the data file itself.
            switch(tag.name)
            {
                case "file":
                    auto path = tag.expectValue!string;
                         path = buildNormalizedPath(baseDir, tag.expectValue!string);

                    files ~= FileInfo(path, null, attribs);
                    break;

                case "namedFile":
                    auto values = tag.values;
                    enforce(values.length == 2, "Expected 2 values for 'namedFile' tag, got %s values instead.".format(values.length));

                    // [0] = name. [1] = path.
                    auto path = values[1].get!string;
                         path = buildNormalizedPath(baseDir, path);

                    files ~= FileInfo(path, values[0].get!string, attribs);
                    break;

                case "glob":
                    warning("Glob searches are not implemented.");
                    /*
                    import std.file : dirEntries, SpanMode;

                    auto glob = tag.expectValue!string;
                    trace("bding");
                    foreach(entry; dirEntries(baseDir, glob, SpanMode.breadth))
                    {
                        FileInfo fi;
                        getParams(fi, tag);
                        fi.path = entry.name;
                        files ~= fi;
                    }*/
                    break;

                default:
                    enforce(false, "Unknown file tag called '%s'.".format(tag.name));
            }

            return files;
        }
    }

    ///
    this()
    {
        auto animExt  = new AnimationExtensionSDL();
        auto namedExt = new NamedFileExtensionSDL();
        super.setExtensionFor("Font",                  namedExt);
        super.setExtensionFor("Sound",                 namedExt);
        super.setExtensionFor("Texture",               namedExt);
        super.setExtensionFor("Sprite:atlas",          new SpriteAtlasExtensionSDL());
        super.setExtensionFor("Animation:list",        animExt);
        super.setExtensionFor("Animation:spriteSheet", animExt);
        super.setExtensionFor("UI:view",               new UIViewExtensionSDL());
    }

    public override
    {
        void loadPackage(const(char[]) filePath)
        {
            super.cleanLoadingState();
            tracef("Loading SDL package at path '%s'", filePath);

            auto path       = (filePath.isAbsolute) ? filePath.idup : filePath.idup.absolutePath;
            auto baseDir    = path.dirName;
            auto packageSDL = parseFile(path);

            enforce(packageSDL.expectTagValue!string("type") == "Package");

            auto name = packageSDL.expectTagValue!string("name");
            super.setPackageName(name);

            tracef("Loading SDL package called '%s'", name);

            foreach(tag; packageSDL.tags)
            {
                switch(tag.name)
                {
                    case "type":
                    case "name":
                        break;

                    case "files":
                        infof("Using an SDLang file list.");
                        auto files = tag.tags.map!(t => this.getFileInfo(baseDir, t));

                        foreach(fileArray; files)
                        foreach(file; fileArray)
                        {
                            infof("File found, '%s'", file.path);
                            auto contents = readText(file.path);

                            // The first line must always be the type.
                            auto firstLine = contents.splitter('\n').front;
                            auto type      = parseSource(firstLine).expectTagValue!string("type");
                            auto extension = super.getExtensionFor(type);

                            super.addLoadingTask(extension, cast(const(ubyte[]))contents, Loader.DebugInfo(file.path));
                        }
                        break;

                    case "namedFiles":
                        auto type  = tag.expectAttribute!string("type");
                        auto files = tag.tags.map!(t => this.getFileInfo(baseDir, t));
                        infof("Using a list of named files, with type of '%s'", type);

                        auto extension = super.getExtensionFor(type);
                        foreach(fileArray; files)
                        foreach(file; fileArray)
                        {
                            infof("File found, '%s'", file.path);
                            auto data = [NamedFileInfo(file.name, file.path, type, file.attributes)];
                            super.addLoadingTask(extension, cast(const(ubyte[]))data, Loader.DebugInfo(file.path));
                        }
                        break;

                    default:
                        throw new Exception(tag.name);
                }
            }

            super.doTasks();
            super.finalisePackage();
        }
    }
}

/++
 + This class is a 'helper' base class which handles converting the `data` sent to the `onLoadAssets` function
 + into the data generated by the 'namedFile' tag, and then passing it along to the `onLoadNamedFileAssets` function.
 +
 + Essentially, this class is used whenever an extension for a 'namedFile' needs to be made, as it gives the implementor
 + a more high level version of the 'onLoadAssets' function to implement since they don't have to deal with a byte array.
 + ++/
abstract class LoaderExtensionSDLNamedFile : LoaderExtension
{
    override final PackageAsset[] onLoadAssets(Loader loader, const(ubyte[]) data)
    {
        // The data is a NamedFileInfo[] that's casted to a ubyte[].
        auto array = cast(LoaderSDL.NamedFileInfo[])data;
        assert(array.length == 1, "Either this wasn't updated to match a new data format, or this function wasn't called by a 'namedFile' tag.");

        auto info = array[0];
        return this.onLoadNamedFileAssets(loader, info.name, info.path, info.type, info.attributes);
    }

    /++
     + Achieves the same task as `onLoadAssets`, except the `data` byte array has been converted into
     + it's actual data.
     +
     + Example:
     +  The following SDLang tag '`namedFiles type="Texture" { namedFile "Error" "Textures/Error.png" someAttrib="hello" attrib2="boobies" }`' would produce
     +  these parameters - assetName="Error". assetPath="Textures/Error.png". assetType="Texture". attributes=["someAttrib": "hello", "attrib2": "boobies"].
     +
     + Params:
     +  loader     = The loader using this extension.
     +  assetName  = The name given to the asset by the 'namedFile' tag.
     +               Unless it's vital for the loading in of the asset, this should be the name given to it.
     +  assetPath  = The path to the file that contain's the asset's data.
     +  assetType  = The type associated with the asset, provided by the 'namedFiles' tag.
     +  attributes = The attributes added to the asset.
     +
     + Returns:
     +  See `Loader.onLoadAssets`.
     + ++/
    abstract PackageAsset[] onLoadNamedFileAssets(Loader loader, string assetName, string assetPath, string assetType, string[string] attributes);
}

/++
 + This class is a 'helper' base class which handles converting the `data` sent to the `onLoadAssets` function
 + into the data generated by the 'file' or 'glob' tags, and then passing it along to the `onLoadFileAssets` function.
 +
 + Essentially, this class is used whenever an extension for a 'file' needs to be made, as it gives the implementor
 + a more high level version of the 'onLoadAssets' function to implement since they don't have to deal with a byte array.
 + ++/
abstract class LoaderExtensionSDLFile : LoaderExtension
{
    override final PackageAsset[] onLoadAssets(Loader loader, const(ubyte[]) data)
    {
        // The data is a string, that's casted to a ubyte[].
        // The string is the contents of the file specified by the 'file' or 'glob' tags.
        auto contents = cast(string)data;
        return this.onLoadFileAssets(loader, parseSource(contents));
    }

    /++
     + Achieves the same task as `onLoadAssets`, except the `data` byte array has been converted into
     + it's actual data.
     +
     + Example:
     +  The following SDLang tag '`files { file "Animations/test.sdl" }`', would mean that the `fileTag` parameter,
     +  is the parsed version of the contents in the "Animations/test.sdl" file.
     +
     +  Reminder that every SDLang file used with the loader system must start with a 'type' tag, and that this
     +  function is only called for files who's 'type' tag matches any of the types that this extension was registered with.
     +
     + Params:
     +  fileTag = The parsed contents of the asset's .sdl file.
     +
     + Returns:
     +  See `Loader.onLoadAssets`.
     + ++/
    abstract PackageAsset[] onLoadFileAssets(Loader loader, Tag fileTag);
}

/++
 + An extension that can load in named files for the engine's assets that aren't covered by the
 + other premade extensions.
 + 
 + Notes:
 +  Like the other premade extensions in this module, the `LoaderSDL` class will automatically register
 +  this extension for it's respective data types.
 +
 +  Files of type 'Sound' support the 'stream' attribute. If 'stream' is set to 'yes', then the
 +  file is loaded as a streaming sound (See `Sound.ctor' for info). Otherwise, if it's set to 'no' or doesn't
 +  exist, the sound is loaded in as a normal sound.
 +
 + Usage:
 +  This extension can handle loading in 'Texture', 'Sound', and 'Font's.
 +
 +  This extension is meant to be used for namedFiles.
 +
 + Example:
 + ```
 + type "Package"
 + name "Example"
 +
 + namedFiles type="Sound" {
 +      namedFile "JumpSound" "Sounds/Jump.wav" stream="no"
 +      namedFile "BackgroundMusic" "Music/bg.wav" stream="yes"
 + }
 + ```
 + ++/
class NamedFileExtensionSDL : LoaderExtensionSDLNamedFile
{
    override PackageAsset[] onLoadNamedFileAssets(Loader loader, string assetName, string assetPath, string assetType, string[string] attributes)
    {
        switch(assetType)
        {
            case "Texture":
                return [PackageAsset(assetName, new Texture(assetPath))];

            case "Sound":
                auto isStreaming = (attributes.get("stream", "no") == "yes") ? Yes.streaming : No.streaming;
                return [PackageAsset("", new DelayedLoadAsset(() => [PackageAsset(assetName, new Sound(assetPath, isStreaming))]))]; // FMOD crashes in fibers

            case "Font":
                return [PackageAsset(assetName, new Font(assetPath))];

            default:
                throw new Exception(assetType);
        }
    }
}

/++
 + An extension that can load in .sdl files that describe a `SpriteAtlas`.
 + 
 + Notes:
 +  Like the other premade extensions in this module, the `LoaderSDL` class will automatically register
 +  this extension for it's respective data types.
 +
 + Usage:
 +  This extension can handle loading in .sdl files of the type 'Sprite:atlas`.
 +
 +  This extension is meant to be used for files (not namedFiles).
 +
 + Example:
 + Package.sdl
 + ```
 + type "Package"
 + name "Example"
 +
 + files {
 +      file "Atlases/Character.sdl"
 + }
 + ```
 +
 + Atlases/Character.sdl
 + ```
 + type "Sprite:atlas"
 + name "atlas_Character"
 + textureRef "texture_CharacterAtlas"
 + 
 + // Any number of 'sprite' tags can be given
 + sprite "Helmet" { // "Helmet" is the name of this sprite.
 +      position 0 0 // The top left corner of the sprite
 +      size 32 32   // The size of the sprite, in pixels.
 + }
 + 
 + // Any number of 'spriteSheet' tags can be given
 + spriteSheet "WalkAnimationSheet" {
 +      position 32, 0
 +      size 64, 64
 +      frameSize 32 32 // How big a single sprite in the sheet is.
 + }
 + ```
 + ++/
class SpriteAtlasExtensionSDL : LoaderExtensionSDLFile
{
    private
    {
        @Name("Sprite:atlas")
        struct AtlasData
        {
            string name;
            string textureRef;
            SpriteData[] sprites;
            SpriteSheetData[] spriteSheets;
        }

        @Name("sprite")
        struct SpriteData
        {
            @MainValue
            string name;

            int[2] position;
            int[2] size;
        }

        @Name("spriteSheet")
        struct SpriteSheetData
        {
            @MainValue
            string name;

            int[2] position;
            int[2] size;
            int[2] frameSize;
        }
    }

    override PackageAsset[] onLoadFileAssets(Loader loader, Tag sdl)
    {
        sdl = sdl.expectTag("Sprite:atlas");
        auto name = sdl.expectTagValue!string("name");
        infof("Loading SpriteAtlas called '%s'", name);

        auto textureName = sdl.expectTagValue!string("textureRef");
        auto texture     = super.waitForAsset!Texture(loader, textureName);
        auto atlas       = new SpriteAtlas(texture);

        auto archive = new ArchiveSDL();
        archive.loadFromTag(sdl);

        auto data = Serialiser.deserialise!AtlasData(archive.root);

        foreach(sprite; data.sprites)
        {
            infof("Loading sprite named '%s'", sprite.name);
            atlas.register(sprite.name, RectangleI(ivec2(sprite.position), ivec2(sprite.size)));
        }

        foreach(sheet; data.spriteSheets)
        {
            infof("Loading sprite sheet named '%s'", sheet.name);
            atlas.registerSpriteSheet(sheet.name, RectangleI(ivec2(sheet.position), ivec2(sheet.size)), ivec2(sheet.frameSize));
        }

        return [PackageAsset(name, atlas)];
    }
}

/// TODO: Document this.
class AnimationExtensionSDL : LoaderExtensionSDLFile
{
    private
    {
        @Name("Animation:list")
        struct ListData
        {
            SpriteSheetData[] sheets;
        }

        @Name("spriteSheet")
        struct SpriteSheetData
        {
            string name;
            string atlasRef;
            string spriteSheetRef;
            uint frameDelayMS;
            bool repeat;
        }

        PackageAsset[] onLoadSpriteSheet(Loader loader, SpriteSheetData sheet)
        {
            // Read in SDLang data
            auto name = sheet.name;
            infof("Loading SpriteSheet animation called '%s'", name);

            auto atlasName       = sheet.atlasRef;
            auto spriteSheetName = sheet.spriteSheetRef;
            auto frameDelayMS    = sheet.frameDelayMS.msecs;
            auto repeat          = sheet.repeat;

            infof("[Name='%s'|Atlas='%s'|FrameDelay=%s ms|Repeating=%s]",
                  name, atlasName, frameDelayMS, repeat);

            // Get the atlas
            auto atlas = super.waitForAsset!SpriteAtlas(loader, atlasName);
            assert(atlas !is null);

            // Then create the object.
            AnimationInfo info;
            info.name          = name;
            info.spriteSheet   = atlas.getSpriteSheet(spriteSheetName);
            info.delayPerFrame = frameDelayMS;
            info.repeat        = repeat;

            return [PackageAsset(name, new StructWrapperAsset!AnimationInfo(info))];
        }
    }

    override PackageAsset[] onLoadFileAssets(Loader loader, Tag fileTag)
    {
        fileTag = fileTag.expectTag("Animation:list");
        auto archive = new ArchiveSDL();
        archive.loadFromTag(fileTag);

        PackageAsset[] assets;
        auto data = Serialiser.deserialise!ListData(archive.root);

        foreach(sheet; data.sheets)
            assets ~= this.onLoadSpriteSheet(loader, sheet);

        return assets;
    }
}

class UIViewExtensionSDL : LoaderExtensionSDLFile
{
    override PackageAsset[] onLoadFileAssets(Loader loader, Tag fileTag)
    {
        fileTag = fileTag.expectTag("UI:view");
        auto archive = new ArchiveSDL();
        archive.loadFromTag(fileTag);

        return [PackageAsset(fileTag.expectTagValue!string("name"), DataBinder.parseView(archive.root))];
    }
}