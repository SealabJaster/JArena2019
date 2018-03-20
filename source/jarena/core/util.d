///
module jarena.core.util;

private
{
    import std.experimental.logger;
    import jarena.core.maths;
    import derelict.sfml2.system, derelict.sfml2.graphics;
}

private enum isSFMLVector(T) = (is(T == sfVector2f) || is(T == sfVector2i) || is(T == sfVector2u));
private enum isSFMLRect(T)   = (is(T == sfFloatRect) || is(T == sfIntRect));
private enum isDLSLVector(T) = isVector!T;
private enum isJArenaRect(T) = (is(T == RectangleF) || is(T == RectangleI)); // TODO : Generic test for rects, instead of a hard coded one

/// Implementation of the `to` function for - DLSL Vector -> SFML Vector
sfVect toSF(sfVect, dlslVect)(dlslVect vect)
if(isSFMLVector!sfVect && isDLSLVector!dlslVect)
{
    static assert(dlslVect.dimension == 2, "Since the SFML vectors we're using are all 2D, we go off the assumption that the DLSL one is also 2D");
    return sfVect(vect.x, vect.y);
}
///
unittest
{
    assert(ivec2(20, 40).toSF!sfVector2i == sfVector2i(20, 40));
}

/// Implementation of the `to` function for - Colour -> sfColor
sfColor toSF(T : sfColor)(Colour vect)
{
    return sfColor(vect.r, vect.g, vect.b, vect.a);
}

/// Implementation of the `to` function for - RectangleI -> sfIntRect
sfIntRect toSF(T : sfIntRect)(RectangleI intRect)
{
    return sfIntRect(intRect.position.x, intRect.position.y, intRect.size.x, intRect.size.y);
}

/// Implemntation of the `to` function for - RectangleF -> sfFloatRect
sfFloatRect toSF(T : sfFloatRect)(RectangleF floatRect)
{
    return sfFloatRect(floatRect.position.x, floatRect.position.y, floatRect.size.x, floatRect.size.y);
}

/// Implementation of the `to` function for - SFML Vector -> DLSL Vector
dlslVect to(dlslVect, sfVect)(sfVect vect)
if(isSFMLVector!sfVect && isDLSLVector!dlslVect)
{
    static assert(dlslVect.dimension == 2, "Since the SFML vectors we're using are all 2D, we go off the assumption that the DLSL one is also 2D");
    return dlslVect(vect.x, vect.y);
}
///
unittest
{
    assert(sfVector2i(20, 40).to!ivec2 == ivec2(20, 40));
}

/// Implementation of the `to` function for - SFML Rectangle -> JArena Rectangle
jarenaRect to(jarenaRect, sfRect)(sfRect rect)
if(isSFMLRect!sfRect && isJArenaRect!jarenaRect)
{
    alias V = jarenaRect.VecType;
    return jarenaRect(V(rect.left, rect.top), V(rect.width, rect.height));
}

/// Implementation of the `to` function for - sfColor -> Colour
Colour to(T : Colour)(sfColor colour)
{
    return Colour(colour.r, colour.g, colour.b, colour.a);
}

// This exists since I don't like the output for the default logger.
/// A custom logger that logs to the console.
final class ConsoleLogger : Logger
{
    import std.datetime;
    
    private
    {
        @safe
        string formatSysTime(SysTime time)
        {
            import std.conv   : to;
            import std.string : rightJustify;
            import std.format : format;

            return format("%s-%s-%s %s:%s:%s:%sms",
                          time.day.to!string.rightJustify(2, '0'),
                          time.month,
                          time.year,

                          time.hour.to!string.rightJustify(2, '0'),
                          time.minute.to!string.rightJustify(2, '0'),
                          time.second.to!string.rightJustify(2, '0'),
                          time.fracSecs.split!"msecs".msecs
                         );
        }
    }
    
    public
    {
        @safe
        this(LogLevel level)
        {
            super(level);
        }

        override void writeLogMsg(ref LogEntry entry)
        {
            import std.algorithm : substitute, map;
            import std.range     : split;
            import std.conv      : to;
            import std.uni       : toUpper;
            import std.stdio     : writefln;

            writefln("[%s](%s$%s:%s)<%s> -> %s",
                     this.formatSysTime(entry.timestamp),
                     entry.file.substitute!("source/",  "", 
                                            "source\\", "",
                                            ".d",       "",
                                            "/",        ".",
                                            "\\",       "."),
                     entry.funcName.split(".")[$-1],
                     entry.line,
                     entry.logLevel.to!string.map!toUpper,
                     entry.msg
                    );
        }
    }
}
