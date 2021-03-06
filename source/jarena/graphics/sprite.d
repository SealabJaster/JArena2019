/++
 + Contains code related to Sprites and Textures.
 + ++/
module jarena.graphics.sprite;

private
{
    import std.experimental.logger;
    import sdlang;
    import jarena.core, jarena.gameplay, jarena.graphics, jarena.maths;
    import opengl, derelict.opengl.versions.base;

    const TEXTURE_DUMP_DIRECTORY = "data/debug/compound/";
}

/++
 + The base class for all textures.
 +
 + Notes:
 +  This class mostly exists to make it easier for the internal rendering code to work with different
 +  texture types, so only the bare minimum is needed for inheriting classes.
 + ++/
abstract class TextureBase : IDisposable
{
    public abstract
    {
        /++
         + Binds this texture as the active texture.
         +
         + Mostly only for internal use.
         + ++/
        void use();

        /++
         + Notes:
         +  This function doesn't have to return the actual size of the internal texture,
         +  but only the size of which the user needs to know about.
         +
         +  For example, the `Texture` class will internally point to a mega-texture that's
         +  something like 2048x2048, but it only uses, say, 256x256 pixels of that texture.
         +  The 256x256 is the size that it should return in that case.
         +
         + Returns:
         +  The size of the texture.
         + ++/
        @safe @nogc
        const(uvec2) size() nothrow const;
    }
}

/++
 + A texture (that lives on the GPU) which can be modified.
 +
 + The main feature of this class is it's `MutableTexture.stitch` function.
 + ++/
class MutableTexture : TextureBase
{
    private
    {
        uint _textureID;
        const(uvec2) _size;
        uint xOffset;  // TODO: Condense xOffset and nextY into `vec2 offset;`
        uint nextY;    // The Y axis of the next texture to stitch.
        uint largestY; // Stores the Y axis of the largest thing stitched on. Gets reset anytime the nextY value is moved.
    }

    public
    {
        /++
         + Creates a new mutable texture with a specific size.
         +
         + Notes:
         +  Currently, specifying a size that is bigger than the GPU supports is undefined behaviour (probably a crash).
         + ++/
        @trusted
        this(const uvec2 size)
        {
            this._size = size;

            // Generate the texture.
            glGenTextures(1, &this._textureID);
            assert(this._textureID > 0, "The texture couldn't be made");
            glBindTexture(GL_TEXTURE_2D, this._textureID);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size.x, size.y, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
            GL.checkForError();
        }

        ~this()
        {
            if(_textureID > 0)
                glDeleteTextures(1, &this._textureID);
        }

        /// Post Frame Dispose
        void dispose(ScheduledDispose scheduled = ScheduledDispose.no)
        {
            if(this.isDisposed)
                return;

            if(!scheduled)
                Systems.shortTermScheduler.postFrameDispose(this);
            else
            {
                glDeleteTextures(1, &this._textureID);
                this._textureID = 0;
            }
        }

        /++
         + Binds this texture as the active texture.
         +
         + Mostly only for internal use.
         + ++/
        override void use()
        {
            assert(!this.isDisposed, "This texture has been disposed of.");
            glBindTexture(GL_TEXTURE_2D, this._textureID);
        }

        /// Returns: The size of the entire texture.
        @property @safe @nogc
        override const(uvec2) size() nothrow const
        {
            return this._size;
        }

        ///
        @property
        bool isDisposed()
        {
            return this._textureID == 0;
        }

        /++
         + Stitches an array of pixels into the texture.
         +
         + Algorithm:
         +  Textures are placed from left to right, tightly packed between eachother on the X axis (no gaps).
         +
         +  The height of the biggest texture is kept track of, this will be referred to as 'H'.
         +
         +  Whenever a texture would be stitched off to the right side of the texture (because there's not enough space)
         +  then we 'move down' the Y axis by 'H'. 'H' is then set to 0, and the process repeats itself.
         +
         +  It is far from perfect, but it is suitable for now.
         +
         + Params:
         +  ColourFormat = Any colour format that is supported by `opengl.GL.getInfoFor`.
         +                 Specifies the format of the data contained in `pixels`.
         +  size         = The size of the image contained in `pixels`.
         +  area         = This will be set to the area of the texture that `pixels` was stitched onto.
         +
         + Returns:
         +  `true` if the stitch was successful.
         +
         +  `false` if there isn't enough room to stitch the texture.
         + ++/
        bool stitch(GLenum ColourFormat)(const ubyte[] pixels, const ivec2 size, out RectangleI area)
        {
            enum ColourInfo = GL.getInfoFor!ColourFormat;

            // Error checking
            assert(!this.isDisposed, "This texture has been disposed of.");

            enforceAndLogf((pixels.length % ColourInfo.bytesPerPixel) == 0,
                "The given pixel array needs to be a multiple of %s. It's length is %s.",
                ColourInfo.bytesPerPixel, pixels.length
            );

            // Calculate how many bytes there are per row, and in total, then make sure it matches up with the array given.
            auto bytesPerRow    = (ColourInfo.bytesPerPixel * size.x);
            auto expectedBytes  = (size.y * bytesPerRow);
            enforceAndLogf(pixels.length == expectedBytes,
                "The given pixel array needs to have a length of %s, to match the given size of %s. It's length is %s",
                expectedBytes, size, pixels.length
            );

            // Move the nextY value down if we've reached the edge of the texture.
            if(size.x + this.xOffset > this._size.x)
            {
                this.xOffset  = 0;
                this.nextY   += this.largestY;
                this.largestY = 0;
            }

            // Using our current algorithm, once we reach the bottom of the texture, there's no room.
            if(size.y + this.nextY > this._size.y)
            {
                warningf("There is not enough room for the texture. MegaH: %s. CursorY: %s. TextureH: %s",
                          this._size.y, this.nextY, size.y);
                return false;
            }

            // Transfer the pixels over
            this.use();
            glTexSubImage2D(
                GL_TEXTURE_2D,
                0,
                xOffset,
                (this.size.y - nextY) - size.y, // yoffset, with some maths so we can work from the top-left
                size.x,
                size.y,
                ColourInfo.bufferType,
                GL_UNSIGNED_BYTE,
                cast(void*)pixels.ptr
            );
            GL.checkForError();

            // Increase the X-offset (The y-offset increase is handled above)
            area = RectangleI(this.xOffset, this.nextY, size);
            
            if(size.y > this.largestY)
                this.largestY = size.y;
            this.xOffset += size.x;

            return true;
        }

        /++
         + Stitches a texture into this texture.
         +
         + Algorithm:
         +  Fetch the pixel data for `texID` in RGBA format.
         +
         +  Call `MutableTexture.stitch`(GLenum)(ubyte[], ivec2, out RectangleI) to perform the actual stitching.
         +
         + Returns:
         +  `true` if the stitch was successful.
         +
         +  `false` if there isn't enough room to stitch the texture.
         + ++/
        bool stitch(uint texID, out RectangleI area)
        {
            import std.experimental.logger;
            tracef("Attempting to stitch texture with ID of %s", texID);
            
            // Figure out the size
            ivec2 size;
            glBindTexture(GL_TEXTURE_2D, texID);
            glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH,  &size.components[0]);
            glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &size.components[1]);
            tracef("The texture has a size of %s", size);

            // Allocate enough memory to load it from the GPU
            import core.stdc.stdlib : malloc, free;
            auto totalBytes = (size.y * size.x) * 4; // OpenGL will convert the texture's data to RGBA for us.
            auto bytes      = (cast(ubyte*)malloc(totalBytes))[0..totalBytes];
            scope(exit) free(bytes.ptr);

            glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, cast(void*)bytes.ptr);
            GL.checkForError();

            // Perform the stitch.
            return this.stitch!GL_RGBA8(bytes, size, area);
        }

        /++
         + Dumps the pixel data of this texture into a file.
         +
         + Notes:
         +  The directory that the file is outputted in is defined by `TEXTURE_DUMP_DIRECTORY`,
         +  which is a private constant variable, so the source will have to be changed to change
         +  the output directory.
         +
         + Params:
         +  id = The name to give the file.
         + ++/
        void dump(string id)
        {
            import derelict.freeimage.freeimage;
            import std.file : exists, mkdirRecurse;
            if(!TEXTURE_DUMP_DIRECTORY.exists)
                mkdirRecurse(TEXTURE_DUMP_DIRECTORY);

            info("Allocating FreeImage buffer");
            auto size  = this.size;
            auto image = FreeImage_Allocate(size.x, size.y, 32);
            scope(exit) FreeImage_Unload(image);
            
            // I don't gain much by using the GC here.
            info("Allocating pixel buffer");
            import core.stdc.stdlib : malloc, free;
            auto totalBytes = (size.y * size.x) * Colour.sizeof;
            auto buffer     = (cast(ubyte*)malloc(totalBytes))[0..totalBytes];
            scope(exit)
            {
                if(buffer.ptr !is null)
                    free(buffer.ptr);
            }
            infof("Buffer size in bytes: %s", buffer.length);

            if(buffer.ptr is null)
            {
                error("Malloc returned null when allocating the buffer. Aborting dump.");
                return;
            }

            info("Getting pixel data from OpenGL");
            this.use();
            glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, cast(void*)buffer.ptr);
            GL.checkForError();

            RGBQUAD quad;
            uint x, y;
            foreach(i2; 0..buffer.length / 4)
            {
                auto bgra = buffer[i2*4..(i2*4)+4];
                quad = RGBQUAD(bgra[2], bgra[1], bgra[0], bgra[3]);

                FreeImage_SetPixelColor(image, x, y, &quad);
                x += 1;

                if(x >= size.x)
                {
                    y += 1;
                    x = 0;
                }
            }
            
            auto fileName = TEXTURE_DUMP_DIRECTORY~(id~".png\0");
            infof("Writing to file '%s'", fileName);
            FreeImage_Save(FIF_PNG, image, fileName.ptr);
        }
    }
}

/++
 + Contains a texture.
 +
 + Notes:
 +  In most cases, you will want this class for texturing.
 +
 +  This class will call into the game's renderer to stitch it's loaded data into
 +  one of it's mega `MutableTextures`, which is then what is actually used for rendering.
 +
 +  This allows for many textures to be batched into a single one, meaning that any sprites using this texture,
 +  can also be batched together with sprites using other textures that happen to point to the same mega texture.
 +
 +  Aka. things are faster (probably).
 + ++/
class Texture : TextureBase
{
    private
    {
        RendererResources.TextureHandle _handle;

        @property @safe @nogc
        inout(typeof(_handle)) handle() nothrow inout
        {
            assert(!this._handle.isNull, "This handle is null.");
            return this._handle;
        }
    }

    public
    {
        /++
         + Creates a new texture from the given path.
         +
         + Params:
         +  filePath = The path to the texture to load.
         + ++/
        @trusted
        this(string filePath)
        {
            tracef("Loading texture at path '%s'", filePath);
            auto texID   = this.loadImage(filePath);
            this._handle = Systems.renderResources.finaliseTexture(texID);
            this.handle(); // For the null assert check
        }

        /++
         + Binds this texture as the active texture.
         +
         + Mostly only for internal use.
         + ++/
        override void use()
        {
            this._handle.bind();
        }

        /++
         + Post Frame Dispose.
         +
         + Notes:
         +  Because under the hood this class references a mega texture, disposing this object
         +  won't dispose of the underlying texture. In it's current form, it doesn't actually
         +  do much at all, but in the future once a better texture packing algorithm is implemented,
         +  the space being used up in the mega texture can be flagged for reuse by disposing of textures.
         + ++/
        void dispose(ScheduledDispose scheduled = ScheduledDispose.no)
        {
            if(this.isDisposed)
                return;

            if(!scheduled)
                Systems.shortTermScheduler.postFrameDispose(this);
            else
                this._handle.dispose();
        }

        /++
         + When comparing two `Texture`s for equality, what actually happens is that
         + a comparison between the underlying, mega `MutableTexture` is performed.
         +
         + This $(B may) be undesirable behaviour, but it's an unfortunate tradeoff.
         + ++/
        override bool opEquals(Object o)
        {
            auto tex = cast(Texture)o;
            if(tex is null)
                return false;

            // Note: This calls TextureHandle.opEquals, which tests
            // if the internal compound textures are the same. (i.e. _handle.area is ignored)
            return (this._handle == tex._handle);
        }

        /// Returns: The size of this texture.
        @property @trusted @nogc
        override const(uvec2) size() nothrow const
        {
            return uvec2(this._handle.area.size);
        }

        ///
        @property
        bool isDisposed()
        {
            return this._handle.isNull;
        }
    }

    // This function is massive, so it can go at the bottom.
    enum GL_NEAREST = 0x2600; // For some reason it can't find this normally...
    private uint loadImage(string filePath, GLenum minFilter = GL_NEAREST, GLenum magFilter = GL_NEAREST)
    {
        import std.format       : format;
        import std.file         : exists;
        import std.string       : toStringz;
        import std.exception    : enforce;
        import derelict.freeimage.freeimage;

        enforce(filePath.exists, format("Cannot load texture at '%s' since it does not exist.", filePath));        
        auto cStrPath = filePath.toStringz;

        // Figure out what the image's format is.
        auto imageFormat = FreeImage_GetFileType(cStrPath);
        enforce(imageFormat != -1, format("FreeImage could not find the texture at '%s'", filePath));
        if(imageFormat == FIF_UNKNOWN)
            imageFormat = FreeImage_GetFIFFromFilename(cStrPath);

        enforce(FreeImage_FIFSupportsReading(imageFormat), 
                format("FreeImage doesn't know the format of the texture at '%s'", filePath));

        // Load it in, and make sure it's in the right format (R8G8B8A8)
        auto image = FreeImage_Load(imageFormat, cStrPath);
        auto bpp   = FreeImage_GetBPP(image);
        if(bpp != 32)
        {
            auto temp = FreeImage_ConvertTo32Bits(image); // This is a _copy_
            FreeImage_Unload(image); // Which is why we have to store it in a temp first.
            image = temp;
        }

        // Now setup the OpenGL texture
        auto size   = ivec2(FreeImage_GetWidth(image), FreeImage_GetHeight(image));
        auto pixels = FreeImage_GetBits(image); // FreeImage_Unload frees this data.
        uint texID;
        glGenTextures(1, &texID);
        glBindTexture(GL_TEXTURE_2D, texID);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter);
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_RGBA,
            size.x,
            size.y,
            0,
            GL_BGRA,
            GL_UNSIGNED_BYTE,
            pixels
        );
        GL.checkForError();

        FreeImage_Unload(image);
        return texID;
    }
}

/++
 + Defines a sprite, which is technically just a `Texture` that has a `Transform`,
 + alongside some other goodies.
 + ++/
class Sprite : ITransformable
{
    private
    {
        Transform  _transform;
        Texture    _texture;
        RectangleI _textureRect;
        Vertex[4]  _verts; // [0]TopLeft|[1]TopRight|[2]BotLeft|[3]BotRight
        Vertex[4]  _transformed;
    }

    public
    {
        /++
         + Creates a new sprite, using a given texture.
         +
         + Params:
         +  texture = The `Texture` to use.
         + ++/
        @safe @nogc
        this(Texture texture) nothrow
        {
            assert(texture !is null);
            this._verts = 
            [
                Vertex(vec2(0), vec2(0), Colour.white),
                Vertex(vec2(0), vec2(0), Colour.white),
                Vertex(vec2(0), vec2(0), Colour.white),
                Vertex(vec2(0), vec2(0), Colour.white)
            ];

            this.texture = texture;
            this.textureRect = RectangleI(0, 0, ivec2(texture.size));
        }

        /++
         + Moves the sprite by a certain offset.
         +
         + Params:
         +  offset = The offset to move by.
         + ++/
        @safe @nogc
        void move(vec2 offset) nothrow
        {
            this._transform.translation += offset;
            this._transform.markDirty();
        }

        /++
         + Returns:
         +  The position of this object.
         + ++/
        @property @safe @nogc
        const(vec2) position() nothrow const
        {
            return this._transform.translation;
        }

        /++
         + Sets the position of the transformable object.
         +
         + Params:
         +  pos = The position to set the object at.
         + ++/
        @property @safe @nogc
        void position(vec2 pos) nothrow
        {
            this._transform.translation = pos;
            this._transform.markDirty();
        }

        /++
         + Returns:
         +  The rotation of this object.
         + ++/
        @property @safe @nogc
        const(AngleDegrees) rotation() nothrow const
        {
            return this._transform.rotation;
        }

        /++
         + Sets the rotation of the transformable object.
         +
         + Params:
         +  angle = The rotation to set the object at.
         + ++/
        @property @safe @nogc
        void rotation(AngleDegrees angle) nothrow
        {
            this._transform.rotation = angle;
            this._transform.markDirty();
        }

        /++
         + Sets the scale of the transformable object (default 1).
         +
         + Params:
         +  amount = The amount to scale it by.
         + ++/
        @property @safe @nogc
        void scale(vec2 amount) nothrow
        {
            this._transform.scale = amount;
            this._transform.markDirty();
        }

        /++
         + Returns:
         +  The amount to scale it by.
         + ++/
        @property @safe @nogc
        const(vec2) scale() nothrow const
        {
            return this._transform.scale;
        }

        /++
         + Returns:
         +  The origin of this object.
         + ++/
        @property @safe @nogc
        const(vec2) origin() nothrow const
        {
            return this._transform.origin;
        }

        /++
         + Sets the origin of the transformable object.
         +
         + Params:
         +  point = The point to set the object's origin to.
         + ++/
        @property @safe @nogc
        void origin(vec2 point) nothrow
        {
            this._transform.origin = point;
            this._transform.markDirty();
        }

        /++
         + Returns:
         +  The area of the sprite's texture which is being rendered.
         + ++/
        @property @safe @nogc
        const(RectangleI) textureRect() nothrow const
        {
            return this._textureRect;
        }

        /++
         + Sets the area within the sprite's texture which is used for rendering.
         +
         + Notes:
         +  This will also affect the size of the sprite on screen, as well as the `Sprite.bounds` function.
         + ++/
        @property @safe @nogc
        void textureRect(RectangleI rect) nothrow
        {
            this._textureRect = rect;

            // Reminder: Textures are stitched into singular massive textures
            // So we have to modify the UV a bit to make sure it takes that fact into account.
            auto textureArea  = this.texture._handle.area;
            auto topLeft      = vec2(rect.position + textureArea.position);
            this._verts[0].uv = topLeft + vec2(0, 0);
            this._verts[1].uv = topLeft + vec2(rect.size.x, 0);
            this._verts[2].uv = topLeft + vec2(0, rect.size.y);
            this._verts[3].uv = topLeft + vec2(rect.size.x, rect.size.y);

            auto posRect = RectangleF(0, 0, vec2(rect.size));
            this._verts[0].position = vec2(0);
            this._verts[1].position = posRect.topRight;
            this._verts[2].position = posRect.botLeft;
            this._verts[3].position = posRect.botRight;

            // Make sure that the rectangle doesn't leak out from the alloted area.
            // (Contributed by Dan the Man)
            // The area(inside of the mega texture) that is being used.
            auto area = RectangleF(this._verts[0].uv.x,
                                   this._verts[0].uv.y,
                                   this._verts[1].uv.x - this._verts[0].uv.x,
                                   this._verts[2].uv.y - this._verts[0].uv.y);
            if(area.position.x < topLeft.x // Left
            || area.position.y < topLeft.y // Top
            || area.topRight.x > topLeft.x + textureArea.size.x  // Right 
            || area.botLeft.y  > topLeft.y + textureArea.size.y) // Bottom
            {
                assert(false, "A texture rect has leaked out of it's given area of the mega texture.");
            }

            this._transform.markDirty();
        }

        /// Returns: The texture for this sprite.
        @property @safe @nogc
        inout(Texture) texture() nothrow inout
        {
            return this._texture;
        }

        /++
         + Sets the texture for this sprite.
         +
         + Notes:
         +  This will set the sprite's `Sprite.textureRect` to `(0,0,textureSizeX,textureSizeY)`
         +
         + Params:
         +  texture = The texture to use.
         + ++/
        @property @safe @nogc
        void texture(Texture texture) nothrow
        {
            assert(texture !is null, "The given texture was null.");
            this._texture = texture;
            this.textureRect = RectangleI(0, 0, ivec2(texture.size));
        }

        /// Returns: The colour of this sprite.
        @property @safe @nogc
        const(Colour) colour() nothrow const
        {
            return this._verts[0].colour;
        }

        /++
         + Sets the colour of this sprite.
         +
         + Params:
         +  col = The colour to use.
         + ++/
        @property @safe @nogc
        void colour(Colour col) nothrow
        {
            foreach(ref vert; this._verts)
                vert.colour = col;

            foreach(ref vert; this._transformed)
                vert.colour = col;
        }

        /++
         + Details:
         +  The bounds of a sprite is a 'screen-accurate' rectangle of the sprite.
         +
         +  For example, while you *could* use sprite.position and sprite.texture.size for all your rectangular needs,
         +  what if you end up using sprite.textureRect for something like animation? Well, then all of your code using
         +  sprite.texture.size is gonna be a *little* off.
         +
         +  This function is basically so the `Sprite` class and any inheriting classes can properly provide
         +  a rectangle describing the 'correct' position and size of the sprite in it's current state.
         +
         +  This function does $(B not) have to take rotation into account.
         +
         + Returns:
         +  The bounds of the sprite.
         + ++/
        @property @safe @nogc
        RectangleF bounds() nothrow
        {
            auto rect = this.textureRect;
            return RectangleF(this.position, vec2(rect.size) * this.scale);
        }

        /// Internal use only.
        /// NOTE: These verts will have the model transform already applied
        /// Also: We peform the model transform on the CPU, so we don't have to pass the data to the GPU
        ///       which would (in my beginner mind) make batching impossible.
        @property @safe @nogc
        final Vertex[4] verts() nothrow
        {
            if(this._transform.isDirty)
            {
                this._transformed = this._verts;
                this._transform.transformVerts(this._transformed[]);
            }

            return this._transformed;
        }
    }
}

/++
 + Contains information about a sprite atlas, which is a single texture containing
 + many different sprites, and/or many different sprite sheets.
 + ++/
class SpriteAtlas
{
    /// Contains information about a sprite sheet
    struct Sheet
    {
        /// How many columns the sheet has.
        uint columns;
        
        /// How many rows the sheet has.
        uint rows;

        /// The frames that make up the sheet.
        RectangleI[] frames;

        /// The atlas that the sheet belongs to.
        SpriteAtlas atlas;
        
        ///
        @safe @nogc
        this(SpriteAtlas atlas) nothrow
        {
            this.atlas = atlas;
        }

        /++
         + Gets the frame rect for a certain frame.
         +
         + Params:
         +  column = The column of the frame.
         +  row    = The row of the frame.
         +
         + Returns:
         +  The frame at (column, row).
         + ++/
        @safe
        const(RectangleI) getFrame(uint column, uint row) const
        {
            import std.exception : enforce;
            import std.format : format;

            enforce(column < this.columns, format("The column given was too big. Columns = %s | ColumnWanted = %s (keep in mind it's 0-based)", columns, column));
            enforce(row < this.rows, format("The row given was too big. Rows = %s | RowWanted = %s (keep in mind it's 0-based)", rows, row));

            return this.frames[(this.columns * row) + column];
        }

        /++
         + Creates a new `Sprite` who's texture is set to the texture of the underlying `SpriteAtlas`, and
         + who's texture rect is set to the frame rect of a certain frame.
         +
         + Params:
         +  column   = The column of the frame to use.
         +  row      = The row of the frame to use.
         +  position = The position to set the sprite at.
         +
         + Returns:
         +  The newly made `Sprite`.
         + ++/
        @safe
        Sprite makeSprite(uint column, uint row, vec2 position = vec2(0))
        {
            auto sprite = new Sprite(this.atlas._texture);
            sprite.textureRect = this.getFrame(column, row);
            sprite.position = position;

            return sprite;
        }

        /++
         + Changes the texture rect of the given `sprite` to the frame
         + rect of a certain frame.
         +
         + Params:
         +  sprite = The `Sprite` to modify.
         +  column = The column of the frame to use.
         +  row    = The row of the frame to use.
         +
         + Returns:
         +  `sprite`
         + ++/
        @safe
        Sprite changeSprite(return Sprite sprite, uint column, uint row)
        {
            sprite.textureRect = this.getFrame(column, row);
            return sprite;
        }
    }

    private
    {
        Texture             _texture;
        RectangleI[string]  _sprites;
        Sheet[string]       _spriteSheets;

        @safe
        void enforceFrame(RectangleI frame, string spriteName, string objectName = "sprite frame")
        {
            // Enforce is used here, as this function will most likely be called using data from a file
            // so rather than it being a code bug, it's an input bug.
            import std.exception : enforce;
            import std.format    : format;

            auto texSize = this._texture.size;
            auto maxX = frame.position.x + frame.size.x;
            auto maxY = frame.position.y + frame.size.y;
            enforce(frame.position.x >= 0, format("The X position for %s '%s' cannot be lower than 0. Value = %s", objectName, spriteName, frame.position.x));
            enforce(frame.position.y >= 0, format("The Y position for %s '%s' cannot be lower than 0. Value = %s", objectName, spriteName, frame.position.y));
            enforce(maxX <= texSize.x, format("The %s '%s' is too wide. Atlas width = %s | frameX + frameWidth = %s", objectName, spriteName, texSize.x, maxX));
            enforce(maxY <= texSize.y, format("The %s '%s' is too high. Atlas height = %s | frameY + frameHeight = %s", objectName, spriteName, texSize.y, maxY));
        }
    }

    public
    {
        /++
         + Creates a new SpriteAtlas using the given texture.
         + ++/
        this(Texture texture)
        {
            assert(texture !is null);
            this._texture = texture;
        }

        /++
         + Registers a sprite.
         +
         + Params:
         +  spriteName = The name of the sprite.
         +  frame      = The area of the texture that makes up the sprite.
         + ++/
        @safe
        void register(string spriteName, RectangleI frame)
        {
            import std.exception : enforce;
            import std.format    : format;

            tracef("Registering sprite frame '%s' with frame rect of %s", spriteName, frame);
            enforce((spriteName in this._sprites) is null, format("Attempted to register sprite frame called '%s' twice.", spriteName));
            this.enforceFrame(frame, spriteName, "sprite frame");
            
            this._sprites[spriteName] = frame;
        }

        /++
         + Unregisters a sprite.
         +
         + Params:
         +  spriteName = The name of the sprite to unregister.
         +
         + Returns:
         +  `true` if the sprite was unregistered, `false` otherwise.
         + ++/
        @safe
        bool unregister(string spriteName)
        {
            if((spriteName in this._sprites) !is null)
            {
                this._sprites.remove(spriteName);
                return true;
            }
            else
                return false;
        }

        /++
         + Registers a sprite sheet.
         +
         + Details:
         +  A sprite sheet is like a mini sprite atlas, where it consists of many different frames.
         +  
         +  The difference is that these frames are very closely linked together. An example of this
         +  is that the frames in the sheet may come together to create an animation.
         +
         +  The number of frames in the sheet are worked out like so;
         +  FramesPerRow = `sheet.size.x / frameSize.x`;
         +  Rows = `sheet.size.y / frameSize.y`
         +
         +  As you might have noticed with the calculations above, sprite sheets can only contain frames that are equally sized.
         +  Non-equallly sized frames don't have a solution yet, so you'll have to make one yourself.
         +
         +  There are two ways to access the frames of a sprite sheet.
         +
         +  $(B TODO: Not implemented yet, but this is planned for.)
         +  #1, each frame of the sheet is registered as a normal sprite (using `SpriteAtlas.register`) under the name
         +  of "[sheetName]:[column]_[row]". So for example, the second frame on the third row of a sheet named "Animation"
         +  will have the name of "Animation:1_2" (0-based of course). 
         +
         +  #2, the function `SpriteAtlas.getSpriteSheet` will return a `SpriteAtlas.Sheet` struct, containing
         +  each frame of the sheet, alongside other pieces of information and helper functions to select the frames you want.
         +
         + Params:
         +  sheetName = The name to register the sheet as.
         +  sheetRect = The part of the atlas that contains the sheet.
         +  frameSize = The size of a single frame in the sheet.
         + ++/
        @safe
        void registerSpriteSheet(string sheetName, RectangleI sheetRect, ivec2 frameSize)
        {
            import std.exception : enforce;
            import std.format    : format;

            tracef("Registering sprite sheet called '%s', location in atlas is %s, with a frame size of %s.",
                   sheetName, sheetRect, frameSize);
            enforce((sheetName in this._spriteSheets) is null, format("Attempted to register sprite sheet called '%s' twice.", sheetName));
            enforce(sheetRect.size.x % frameSize.x == 0, 
                    format("The width of the sheet(%s) is not evenly divisible by the width of a frame(%s).", sheetRect.size.x, frameSize.x));
            enforce(sheetRect.size.y % frameSize.y == 0, 
                    format("The height of the sheet(%s) is not evenly divisible by the height of a frame(%s).", sheetRect.size.y, frameSize.y));

            auto sheet = Sheet(this);
            sheet.columns = sheetRect.size.x / frameSize.x;
            sheet.rows = sheetRect.size.y / frameSize.y;
            sheet.frames.reserve(sheet.columns * (sheet.rows + 1));

            tracef("Sprite sheet has %s columns and %s rows.", sheet.columns, sheet.rows);
            foreach(row; 0..sheet.rows)
            {
                foreach(col; 0..sheet.columns)
                {
                    auto frame = RectangleI(frameSize.x * col + sheetRect.position.x, 
                                            frameSize.y * row + sheetRect.position.y, 
                                            frameSize);
                    this.enforceFrame(frame, sheetName, "sprite sheet");
                    sheet.frames ~= frame;
                }
            }

            this._spriteSheets[sheetName] = sheet;
        }

        /// Returns: A sprite `Sheet` that was previously registered.
        @safe
        Sheet getSpriteSheet(string sheetName)
        {
            import std.exception : enforce;
            enforce((sheetName in this._spriteSheets) !is null, "Cannot find sprite sheet called: " ~ sheetName);

            return this._spriteSheets[sheetName];
        }

        /// Returns: The rectangle for a sprite that was previously registered.
        @safe
        RectangleI getSpriteRect(string spriteName)
        {
            import std.exception : enforce;
            enforce((spriteName in this._sprites) !is null, "Cannot find sprite frame called: " ~ spriteName);

            return this._sprites[spriteName];
        }

        /++
         + Creates a new sprite, who's texture is set to the texture of this atlas,
         + and who's texture rect is set to whatever `SpriteAtlas.getSpriteRect(spriteName)` returns.
         +
         + Params:
         +  spriteName = The name of the sprite to use.
         +  position   = The position to give the sprite.
         +
         + Returns:
         +  The newly made `Sprite`.
         + ++/
        @safe
        Sprite makeSprite(string spriteName, vec2 position = vec2(0, 0))
        {
            auto sprite = new Sprite(this._texture);
            sprite.textureRect = this.getSpriteRect(spriteName);
            sprite.position = position;

            return sprite;
        }

        /++
         + Changes the texture rect of the given `sprite` to the sprite frame called
         + `spriteName`
         +
         + Params:
         +  sprite     = The `Sprite` to modify.
         +  spriteName = The name of the sprite frame to use.
         +
         + Returns:
         +  `sprite`
         + ++/
        @safe
        Sprite changeSprite(return Sprite sprite, string spriteName)
        {
            sprite.textureRect = this.getSpriteRect(spriteName);
            return sprite;
        }
        
        /// Returns: The texture of this atlas.
        @property @safe @nogc
        inout(Texture) texture() nothrow inout
        {
            return this._texture;
        }

        /// Returns: KeyValue pair for sprites.
        @property @safe @nogc
        auto bySpriteKeyValue() nothrow inout
        {
            return this._sprites.byKeyValue;
        }

        /// Returns: KeyValue pair for sprite sheets.
        @property @safe @nogc
        auto bySpriteSheetKeyValue() nothrow inout
        {
            return this._spriteSheets.byKeyValue;
        }

        /// Returns: A range going over the names of all registered sprites, in no particular order.
        @property @safe @nogc
        auto bySpriteKeys() nothrow inout
        {
            return this._sprites.byKey;
        }

        /// Returns: A range going over the names of all registered sprite sheets, in no particular order.
        @property @safe @nogc
        auto bySpriteSheetKeys() nothrow inout
        {
            return this._spriteSheets.byKey;
        }
    }
}

/// Contains information about an animation.
struct AnimationInfo
{
    /// The name of the animation.
    string name;

    /// The sprite sheet that contains the animation's frames.
    SpriteAtlas.Sheet spriteSheet;

    /// How much time to wait between each frame.
    Duration delayPerFrame;

    /// Whether the animation should repeat or not.
    bool repeat;
}

/++
 + Adds the ability for a `Sprite` to be animated.
 +
 + There are two built-in ways to animate a sprite using this function.
 +
 + The first is automatic animation, which is where the programmer calls `AnimatedSprite.onUpdate`,
 + which will allow the class to update it's animation with respect to the information within
 + it's current animation (`AnimationInfo`).
 +
 + The second is manual animation, which is where `AnimatedSprite.onUpdate` is $(B not) called, and the programmer
 + instead uses `AnimatedSprite.currentFrame`, `AnimatedSprite.changeFrame`, and `AnimatedSprite.advance` to
 + finely-control the frame that the sprite is displaying.
 +
 + Of course, this class can be inherited from, and other systems can be built to provide different automatic
 + animation options.
 + ++/
class AnimatedSprite : Sprite
{
    private
    {
        Cache!AnimationInfo _animations;

        // Information about the current animation.
        AnimationInfo _currentAnimation;
        uvec2         _currentFrame;
        Duration      _currentDelay;
        bool          _finished;
    }

    public
    {
        /++
         + Notes:
         +  For sprites that have the ability to change animations, it's recommended to only use
         +  `AnimationInfo`s that all come from the same `SpriteAtlas`, as changing textures
         +  might cause peformance issues.
         +
         + Params:
         +  animation  = The sprite's animation.
         +  animations = A cache of different animations.
         +               This can be null, and is only needed for sprites that can change animations.
         + ++/
        @safe
        this(AnimationInfo animation, Cache!AnimationInfo animations = null)
        {
            super(animation.spriteSheet.atlas.texture);

            this.animation = animation;
            this._animations = animations;
        }

        /++
         + Updates the animation.
         +
         + Notes:
         +  If you wish for the animation to be controlled manually/via some other
         +  automated way, please look at `advance`, `retreat`, `currentFrame`,
         +  and `changeFrame`. Remember to stop calling this function as well.
         + ++/
        @safe
        void onUpdate(Duration delta)
        {
            if(this._finished)
                return;

            this._currentDelay += delta;
            if(this._currentDelay >= this.animation.delayPerFrame)
            {
                this.advance(1);
                this.changeFrame();
                this._currentDelay -= this.animation.delayPerFrame;
            }
        }

        /++
         + Changes the current animation using the cache given to this class' constructor.
         +
         + Notes:
         +  If the cache given was null, then this function does nothing.
         +
         + Params:
         +  animName = The name of the animation to lookup in the cache.
         + ++/
        @trusted
        void changeAnimation(string animName)
        {
            if(this._animations !is null)
                this.animation = this._animations.get(animName);
        }

        /++
         + Restarts the animation.
         +
         + For manual animations - this function will reset the `currentFrame` to 0, and then
         + call `changeFrame`.
         + ++/
        @safe
        void restart()
        {
            this._currentDelay = Duration.zero;
            this._finished = false;
            this._currentFrame = uvec2(0);

            if(this._currentAnimation.spriteSheet.columns > 0)
                this.changeFrame();
        }

        /++
         + Update's the sprite to display the `currentFrame` of the animation.
         +
         + Notes:
         +  This function is only useful for manual animations.
         +
         +  If either the x or y position of the `currentFrame` are out of bounds, an assert will fail.
         +  `AnimatedSprite.animation.spriteSheet` will contain the number of columns and rows the animation
         +  contains, which can be used to properly keep them in bounds.
         + ++/
        @safe
        void changeFrame()
        {
            this._currentAnimation.spriteSheet.changeSprite(this, this._currentFrame.x, this._currentFrame.y);
        }

        /++
         + Advances the animation by a certain amount of frames.
         +
         + Notes:
         +  This is likely only useful for manual animations.
         +
         +  This will automatically advance onto the next row (y-axis) of animations if needed.
         +
         +  For non-repeating animations, once the last frame of animation is reached, the current frame
         +  will no longer be altered, and the `finished` flag is set. To clear this flag, a call to
         +  `restart` must be made.
         +
         +  For repeating animations, once the final frame has been reached, this function will simply
         +  loop back to the first frame of animation, and go from there. $(B The `finished` flag will never
         +  be set in this case).
         +
         +  $(B This function only changes the value of `currentFrame`, it does not update the sprite.
         +      Please use the `changeFrame` function to update the sprite to the current frame.)
         +
         +  This function will always keep the `currentFrame` in-bounds, meaning it is safe to call `changeFrame`
         +  without any kind of checking.
         + ++/
        @safe @nogc
        void advance(uint frameCount = 1) nothrow
        {
            @safe @nogc
            void nextFrame() nothrow
            {
                this._currentFrame.x = this._currentFrame.x + 1;
                if(this._currentFrame.x >= this._currentAnimation.spriteSheet.columns)
                {
                    this._currentFrame.x = 0;
                    this._currentFrame.y = this._currentFrame.y + 1;

                    if(this._currentAnimation.repeat && this._currentFrame.y >= this._currentAnimation.spriteSheet.rows)
                        this._currentFrame.y = 0;
                }

                if(this._currentFrame.x >= this.animation.spriteSheet.columns - 1
                && this._currentFrame.y >= this.animation.spriteSheet.rows - 1
                && !this.animation.repeat)
                    this._finished = true;
            }

            // TODO: Make an optimised version of this function.
            foreach(_; 0..frameCount)
            {
                if(!this.finished)
                    nextFrame();
            }
        }

        /++
         + Notes:
         +  This function is generally only useful for manual animations.
         +  Though there are cases you may want this when using an automatic animation.
         +
         +  Because a reference is returned, code such as `myAnimation.currentFrame += uvec2(20, 10)` will work.
         +
         +  A call to `changeFrame` must be made for the sprite to be updated.
         +
         + Returns:
         +  A reference to a vector containing information about the current frame of the animation.
         + ++/
        @property @safe @nogc
        ref inout(uvec2) currentFrame() nothrow inout
        {
            return this._currentFrame;
        }

        /// Sets the current animation of the sprite. (Doesn't require a cache).
        @property @trusted
        void animation(AnimationInfo info)
        {
            // Reset state
            this.restart();
            this._currentAnimation = info;

            this.texture = info.spriteSheet.atlas._texture;
            info.spriteSheet.changeSprite(this, 0, 0);
        }

        /// Returns: The current animation of the sprite.
        @property @safe @nogc
        inout(AnimationInfo) animation() nothrow inout
        {
            return this._currentAnimation;
        }

        /// Returns: Whether the current animation has finished. Always `false` for repeating animations.
        @property @safe @nogc
        bool finished() nothrow const
        {
            return this._finished;
        }
    }
}

/++
 + A simple object that does nothing other than draw an animated sprite to the screen.
 +
 + This class is `alias this`ed to it's sprite, to make it work exactly like a normal sprite.
 + ++/
class AnimatedObject : DrawableObject
{
    alias sprite this;

    private
    {
        AnimatedSprite _sprite;
    }

    public
    {
        /++
         + Creates a new AnimatedObject using a pre-made sprite.
         +
         + Params:
         +  sprite = The Sprite to use.
         +  position = The position to set the sprite at.
         +  yLevel = The yLevel to use
         + ++/
        @safe
        this(AnimatedSprite sprite, vec2 position = vec2(0), int yLevel = 0)
        {
            assert(sprite !is null);
            this._sprite = sprite;
            this.yLevel = yLevel;
            sprite.position = position;
        }

        /// The sprite for this AnimatedObject.
        @property
        AnimatedSprite sprite()
        {
            assert(this._sprite !is null, "The sprite hasn't been created yet.");
            return this._sprite;
        }
    }

    public override
    {
        ///
        void onUnregister(PostOffice office){}
        
        ///
        void onUpdate(Duration deltaTime, InputManager input)
        {
            this._sprite.onUpdate(deltaTime);
        }

        ///
        void onRegister(PostOffice office){}

        ///
        void onRender(Window window)
        {
            window.renderer.drawSprite(this._sprite);
        }
    }
}

/++
 + A simple object that does nothing other than draw a sprite to the screen.
 +
 + This class is `alias this`ed to it's sprite, to make it work exactly like a normal sprite.
 + ++/
class StaticObject : DrawableObject
{
    alias sprite this;

    private
    {
        Sprite _sprite;
        string _texturePath;
        vec2   _initialPosition;
    }

    public
    {
        /++
         + Creates a new StaticObject using a pre-made sprite.
         +
         + Params:
         +  sprite = The Sprite to use.
         +  position = The position to set the sprite at.
         +  yLevel = The yLevel to use
         + ++/
        @safe
        this(Sprite sprite, vec2 position = vec2(0), int yLevel = 0)
        {
            assert(sprite !is null);
            this._sprite = sprite;
            this.yLevel = yLevel;
            sprite.position = position;
        }

        /++
         + Creates a new StaticObject, alongside a new sprite, using a given texture.
         +
         + Params:
         +  texture = The texture to use.
         +  position = The position to set the sprite at.
         +  yLevel = The yLevel to use
         + ++/
        @safe
        this(Texture texture, vec2 position = vec2(0), int yLevel = 0)
        {
            this(new Sprite(texture), position, yLevel);
        }

        /++
         + Creates a new StaticObject, using the texture provided by a path.
         +
         + Notes:
         +  The texture, and therefor the StaticObject's sprite, won't be loaded until
         +  the StaticObject is registered with a scene when this constructor is used.
         +
         +  The texture is loaded using the cache of the current `Scene`'s `SceneManager`.
         +
         + Params:
         +  texturePath = The path to the texture to use.
         +  position = The position to set the sprite at.
         +  yLevel = The yLevel to use
         + ++/
        @safe
        this(string texturePath, vec2 position = vec2(0), int yLevel = 0)
        {
            this._texturePath = texturePath;
            this._initialPosition = position;
            this.yLevel = yLevel;
        }

        /// The sprite for this StaticObject.
        @property
        Sprite sprite()
        {
            assert(this._sprite !is null, "The sprite hasn't been created yet.");
            return this._sprite;
        }
    }

    public override
    {
        ///
        void onUnregister(PostOffice office){}
        
        ///
        void onUpdate(Duration deltaTime, InputManager input){}

        ///
        void onRegister(PostOffice office)
        {
            if(this._sprite is null && this._texturePath !is null)
            {
                assert(false, "Not implemented");
                // I really need to find a clean/shorter way to access that cache T.T
                //auto texture = super.scene.manager.cache.loadOrGet(this._texturePath);
                //this._sprite = new Sprite(texture);
                //this.sprite.position = this._initialPosition;
            }
        }

        ///
        void onRender(Window window)
        {
            window.renderer.drawSprite(this._sprite);
        }
    }
}

/++
 + Will either return a cached texture, or load in, cache, then return a texture.
 +
 + Params:
 +  cache = The texture cache to use.
 +  path = The path to the texture.
 +
 + Returns:
 +  If `cache` contains a texture called `path`, then the cached texture is returned.
 +
 +  Otherwise, a new texture is loaded in from the `path`, cached into the `cache`, and then returned.
 + ++/
Texture loadOrGet(Cache!Texture cache, string path)
{
    auto cached = cache.get(path);
    if(cached is null)
    {
        cached = new Texture(path);
        cache.add(path, cached);
    }

    return cached;
}

/// ditto
Texture loadOrGet(Multi_Cache)(Multi_Cache cache, string path)
if(isMultiCache!Multi_Cache && canCache!(Multi_Cache, Texture))
{
    return cache.getCache!Texture.loadOrGet(path);
}
