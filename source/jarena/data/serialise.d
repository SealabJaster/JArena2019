module jarena.data.serialise;

private
{
    import std.traits;
    import std.format   : format;
    import std.conv     : to;
    import std.typecons : Nullable;
    
    import jarena.data.loaders, jarena.core;
    import codebuilder;
}

public import sdlang;

/++
 + [Optional]
 + Can be used to set a custom name for a variable or struct.
 +
 + SDLang:
 +  For SDLang serialisation, the name is used as the tag name.
 +
 +  e.g. A struct named 'myStruct' might be serialised like
 +  ```
 +  myStruct {
 +     someVar "abcdef"
 +  }
 +  ```
 + ++/
struct Name
{
    string name;
}

/++
 + [Mandatory]
 +  Must be placed on any structs that support serialisation.
 + ++/
struct Serialisable
{}

/++
 + Creates functions used for serialisation.
 + ++/
mixin template SerialisableInterface()
{
    import std.traits : hasUDA;
    import sdlang : Tag;
    
    alias ThisType = typeof(this);
    enum  ThisName = getFieldName!ThisType;
    static assert(hasUDA!(ThisType, Serialisable), "Please attach an @Serialisable to the type: " ~ ThisType.stringof);

    // For the compile time checks
    mixin SerialisableInterfaceManual;

    /++
     + Updates the data in this struct based on the data in the given `tag`.
     + ++/
    void updateFromSdlTag(Tag tag)
    {
        import std.exception : enforce;
        
        //pragma(msg, "For Type: " ~ ThisType.stringof);
        //pragma(msg, fromSdlTagGenerator!ThisType);
        mixin(fromSdlTagGenerator!ThisType);
    }

    /// Returns: The serialisable type created from the given `tag`.
    static ThisType createFromSdlTag(Tag tag)
    {
        ThisType type;
        type.updateFromSdlTag(tag);

        return type;
    }

    /// Returns: An Sdlang `Tag` created from the data in this object.
    Tag saveToSdlTag()
    {
        auto tag = new Tag();
        tag.name = ThisName.name;
        // pragma(msg, "For Type(Serialise): " ~ ThisType.stringof);
        // pragma(msg, toSdlTagGenerator!ThisType);
        mixin(toSdlTagGenerator!ThisType);
        return tag;
    }
}

/++
 + A mixin template that should be used by any @Serialisable type that specifies it's
 + own serialisation functions.
 +
 + All it does is insert some compile time checks to make sure the functions exist, and are properly formed.
 + ++/
mixin template SerialisableInterfaceManual()
{
    import std.traits : hasUDA;
    alias ThisType = typeof(this);

    static assert(hasUDA!(ThisType, Serialisable), "Please attach an @Serialisable to the type: " ~ ThisType.stringof);
    static assert(is(typeof({import sdlang; auto o = ThisType.init; o.updateFromSdlTag(new Tag());})), 
                  "The type '"~ThisType.stringof~"' hasn't implemented the updateFromSdlTag function. 'void updateFromSdlTag(sdlang.Tag tag)'");
    static assert(is(typeof({import sdlang; auto o = ThisType.init; o.createFromSdlTag(new Tag());})), 
                  "The type '"~ThisType.stringof~"' hasn't implemented the createFromSdlTag function. '"~ThisType.stringof~" createFromSdlTag(sdlang.Tag tag)'");
    static assert(is(typeof({import sdlang; auto o = ThisType.init; Tag tag = o.saveToSdlTag();})), 
                  "The type '"~ThisType.stringof~"' hasn't implemented the saveToSdlTag function. 'sdlang.Tag saveToSdlTag()'");
}

// Needs to be public so the mixin template can work.
// But shouldn't be used outside of this module.
string fromSdlTagGenerator(ThisType)()
{
    auto code = new CodeBuilder();
    size_t nameCounter = 0;

    foreach(fieldName; FieldNameTuple!ThisType)
    {
        mixin("alias FieldAlias = ThisType.%s;".format(fieldName));
        alias FieldType     = typeof(FieldAlias);
        enum  FieldTypeName = fullyQualifiedName!FieldType;
        enum  FieldTagName  = getFieldName!FieldAlias.name;

        
        //static if(is(typeof({code.generateSDLDeserialise!(FieldAlias, FieldType, FieldTypeName, FieldTagName, fieldName)(nameCounter);})))
            code.generateSDLDeserialise!(FieldAlias, FieldType, FieldTypeName, FieldTagName, "this." ~ fieldName)(nameCounter);
        //else
            //static assert(false, format("No Deserialiser for field '%s' of type '%s'", fieldName, FieldType.stringof));
    }        
    
    return code.data.idup.to!string;
}

// Ditto
string toSdlTagGenerator(ThisType)()
{
    auto code = new CodeBuilder();
    size_t nameCounter = 0;

    foreach(fieldName; FieldNameTuple!ThisType)
    {
        mixin("alias FieldAlias = ThisType.%s;".format(fieldName));
        alias FieldType     = typeof(FieldAlias);
        enum  FieldTypeName = fullyQualifiedName!FieldType;
        enum  FieldTagName  = getFieldName!FieldAlias.name;

        //static if(is(typeof(code.generateSDLSerialise!(FieldAlias, FieldType, FieldTypeName, FieldTagName, "this." ~ fieldName)(nameCounter))))
            code.generateSDLSerialise!(FieldAlias, FieldType, FieldTypeName, FieldTagName, "this." ~ fieldName)(nameCounter);
    }        
    
    return code.data.idup.to!string;
}

private enum isNullable(T) = isInstanceOf!(Nullable, T);

static Name getFieldName(alias F)()
{
    static if(hasUDA!(F, Name))
        return getUDAs!(F, Name)[0];
    else
        return Name(F.stringof);
}

private string genTempName(ref size_t nameCounter)
{
    import std.conv : to;
    return "var" ~ nameCounter++.to!string;
}

// SDLang deserialise specific functions
// Anytime a new type needs to have a generator for it to be serialised, just make
// a new 'generateSDLDeserialise' function, and change it's contract.
private static
{
    // For builtin types, use expectTagValue, since it already supports them all.
    void generateSDLDeserialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                               (CodeBuilder code, ref size_t nameCounter)
    if(isBuiltinType!FieldType && !isNullable!FieldType)
    {
        code.put("// Builtin Type");
        code.putf("%s = tag.expectTagValue!(%s)(\"%s\");",
                  FieldMemberName, FieldTypeName, FieldTagName);
    }

    // For @Serialisable structs/classes, call their fromSdlTag function.
    void generateSDLDeserialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                               (CodeBuilder code, ref size_t nameCounter)
    if((is(FieldType == struct) || is(FieldType == class)) && !isNullable!FieldType && !isVector!FieldType)
    {
        static assert(hasUDA!(FieldType, Serialisable), "The type "~FieldType.stringof~" doesn't have @Serialisable, so can't be used.");
        static assert(hasMember!(FieldType, "updateFromSdlTag"),
                      format("The @Serialisable type '%s' doesn't have a function called 'updateFromSdlTag', please use `mixin SerialisableInterface;`",
                             FieldType.stringof)
                     );

        code.put("// @Serialisable");
        code.putf("%s = (%s).init;", FieldMemberName, FieldTypeName);
        code.putf("%s.updateFromSdlTag(tag.expectTag(\"%s\"));", FieldMemberName, FieldTagName);
    }

    // For vectors, check that the tag has N amount of values, and then read them into the vector.
    void generateSDLDeserialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                               (CodeBuilder code, ref size_t nameCounter)
    if(isVector!FieldType && !isNullable!FieldType)
    {
        enum N       = FieldType.dimension;
        alias VectT  = Signed!(FieldType.valueType);
        auto varName = genTempName(nameCounter);

        code.put("// Vector type");
        code.putf("Tag %s = tag.expectTag(\"%s\");", varName, FieldTagName);
        code.putf("enforce(%s.values.length == %s, \"Expected %s values for tag '%s' for type '%s'\");",
                  varName, N, N, FieldTagName, FieldTypeName);
                      
        code.putf("foreach(i; 0..%s)", N);
        code.putScope((_)
        {
            code.putf("%s.data[i] = %s.values[i].get!%s;",
                      FieldMemberName, varName, VectT.stringof);
        });
    }

    // For nullables, check to see whether the tag exists.
    // If yes, load it in.
    // If no, set it to `.init` which is by default null for a nullable.
    void generateSDLDeserialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                               (CodeBuilder code, ref size_t nameCounter)
    if(isNullable!FieldType)
    {
        alias NullableInnerType = TemplateArgsOf!(FieldType)[0];
        auto tagName = genTempName(nameCounter);
        
        code.putf("// Nullable of %s", NullableInnerType.stringof);
        code.putf("auto %s = tag.getTag(\"%s\");", tagName, FieldTagName);
        code.putf("if(%s is null) %s.nullify;", tagName, FieldMemberName);
        code.put("else");
        code.putScope((_)
        {
            code.putf("%s = (%s).init;", FieldMemberName, fullyQualifiedName!NullableInnerType);
            code.generateSDLDeserialise!(FieldAlias, 
                                         NullableInnerType, 
                                         fullyQualifiedName!NullableInnerType,
                                         FieldTagName,
                                         FieldMemberName)
                                         (nameCounter);
        });
    }
}

@Serialisable
struct Temp2
{
    mixin SerialisableInterface;

    string b;
}

@Serialisable
struct Temp
{
    mixin SerialisableInterface;

    int b;
    string a;

    Temp2 t;
    vec2 v;
}

// Sdlang serialise generators.
private static
{
    // Built-in types.
    void generateSDLSerialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                             (CodeBuilder code, ref size_t nameCounter)
    if(isBuiltinType!FieldType && !isNullable!FieldType)
    {
        code.put("// Builtin Type");

        auto varName = genTempName(nameCounter);
        code.putf("auto %s = new Tag();", varName);
        code.putf("%s.name = \"%s\";", varName, FieldTagName);
        code.putf("%s.add(Value(%s));", varName, FieldMemberName);
        code.putf("tag.add(%s);", varName);
    }

    void generateSDLSerialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                             (CodeBuilder code, ref size_t nameCounter)
    if((is(FieldType == struct) || is(FieldType == class)) && !isNullable!FieldType && !isVector!FieldType)
    {
        static assert(hasUDA!(FieldType, Serialisable), "The type "~FieldType.stringof~" doesn't have @Serialisable, so can't be used.");
        static assert(hasMember!(FieldType, "updateFromSdlTag"),
                      format("The @Serialisable type '%s' doesn't have a function called 'updateFromSdlTag', please use `mixin SerialisableInterface;`",
                             FieldType.stringof)
                     );

        code.put("// @Serialisable");
        code.putf("tag.add(%s.saveToSdlTag());", FieldMemberName);
    }

    void generateSDLSerialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                             (CodeBuilder code, ref size_t nameCounter)
    if(isVector!FieldType && !isNullable!FieldType)
    {
        enum N       = FieldType.dimension;
        alias VectT  = Signed!(FieldType.valueType);
        auto varName = genTempName(nameCounter);

        code.put("// Vector type");
        code.putf("auto %s = new Tag();", varName);
        code.putf("%s.name = \"%s\";", varName, FieldTagName);
        code.putf("%s.add(Value(cast(%s)%s.data[0]));", varName, VectT.stringof, FieldMemberName);
        code.putf("%s.add(Value(cast(%s)%s.data[1]));", varName, VectT.stringof, FieldMemberName);
        code.putf("tag.add(%s);", varName);
    }

    void generateSDLSerialise(alias FieldAlias, FieldType, string FieldTypeName, string FieldTagName, string FieldMemberName)
                             (CodeBuilder code, ref size_t nameCounter)
    if(isNullable!FieldType)
    {
        alias NullableInnerType = TemplateArgsOf!(FieldType)[0];
        auto tagName = genTempName(nameCounter);
        
        code.putf("// Nullable of %s", NullableInnerType.stringof);
        code.putf("if(!%s.isNull)", FieldMemberName);
        code.putScope((_)
        {
            code.generateSDLSerialise!(FieldAlias,
                                       NullableInnerType,
                                       fullyQualifiedName!NullableInnerType,
                                       FieldTagName,
                                       FieldMemberName~".get()")
                                       (nameCounter);
        });
    }
}