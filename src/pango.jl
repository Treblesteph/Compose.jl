
# Estimation of text extents using pango.

using Fontconfig

const libpangocairo = Cairo._jl_libpangocairo
const libpango = Cairo._jl_libpango

# Cairo text backend
const CAIRO_FONT_TYPE_TOY = 0
const CAIRO_FONT_TYPE_FT = 1
const CAIRO_FONT_TYPE_WIN32 = 2
const CAIRO_FONT_TYPE_QUARTZ = 3
const CAIRO_FONT_TYPE_USER = 4

# Mirroring a #define in the pango header.
const PANGO_SCALE = 1024.0


function pango_fmt_float(x::Float64)
    if x < 0.1
        a = @sprintf("%0.18f", x)
    else
        a = @sprintf("%f", x)
    end

    n = length(a)
    while a[n] == '0'
        n -= 1
    end

    if a[n] == '.'
        n -= 1
    end

    a[1:n]
end


# Use the freetype/fontconfig backend to find the best match to a font
# description.
#
# Args:
#   desc: A string giving the font description. This can
#         also provide a comma-seperated list of families. E.g.,
#         "Helvetica, Arial 10"
#
# Returns:
#   A pointer to a PangoFontDescription with the closest match.
#
let available_font_families = Set{String}()
    for font_pattern in Fontconfig.list()
        push!(available_font_families, lowercase(format(font_pattern, "%{family}")))
    end

    const meta_families = Set(["serif", "sans", "sans-serif", "monospace",
                               "cursive", "fantasy"])

    global match_font
    function match_font(families::String, size::Float64)
        matched_family = "sans-serif"
        for family in [lowercase(strip(family, [' ', '"', '\''])) for family in split(families, ',')]
            if family in available_font_families || family in meta_families
                matched_family = family
                break
            end
        end
        family = format(match(Fontconfig.Pattern(family=family)), "%{family}")
        desc = @sprintf("%s %fpx", family, size)
        fd = ccall((:pango_font_description_from_string, libpango),
                   Ptr{Void}, (Ptr{Uint8},), bytestring(desc))
        return fd
    end
end


# Thin wrapper for a pango_layout object.
type PangoLayout
    layout::Ptr{Void}

    function PangoLayout()
        layout = ccall((:pango_layout_new, libpango),
                       Ptr{Void}, (Ptr{Void},), pango_cairo_ctx)
        # TODO: finalizer?

        new(layout)
    end
end

# Set the layout's font.
function pango_set_font(pangolayout::PangoLayout, family::String, pts::Number)
    fd = match_font(family, pts)
    ccall((:pango_layout_set_font_description, libpango),
          Void, (Ptr{Void}, Ptr{Void}), pangolayout.layout, fd)
end


# Find the width and height of a string.
#
# Args:
#   pangolayout: a pango layout object, with font, etc, set.
#   text: a string we might like to draw.
#
# Returns:
#   A (width, height) tuple in absolute units.
#
function pango_text_extents(pangolayout::PangoLayout, text::String)
    textarray = convert(Vector{Uint8}, bytestring(text))
    ccall((:pango_layout_set_markup, libpango),
          Void, (Ptr{Void}, Ptr{Uint8}, Int32),
          pangolayout.layout, textarray, length(textarray))

    extents = Array(Int32, 4)
    ccall((:pango_layout_get_extents, libpango),
          Void, (Ptr{Void}, Ptr{Int32}, Ptr{Int32}),
          pangolayout.layout, extents, C_NULL)

    width, height = (extents[3] / PANGO_SCALE)pt, (extents[4] / PANGO_SCALE)pt
end


# Find the minimum width and height needed to fit any of the given strings.
#
# (A "user-friendly" wrapper for pango_text_extents.)
#
# Args:
#   font_family: Something like a font name.
#   pts: Font size in points.
#   texts: One or more strings.
#
# Returns:
#   A (width, height) tuple in absolute units.
#
function max_text_extents(font_family::String, pts::Float64, texts::String...)
    pango_set_font(pangolayout::PangoLayout, font_family, pts)
    max_width  = 0mm
    max_height = 0mm
    for text in texts
        (width, height) = pango_text_extents(pangolayout::PangoLayout, text)
        max_width  = max_width.abs  < width.abs  ? width  : max_width
        max_height = max_height.abs < height.abs ? height : max_height
    end
    return (max_width, max_height)
end

# Same as max_text_extents but with font_size in arbitrary absolute units.
function max_text_extents(font_family::String, size::Measure,
                      texts::String...)
    if !isabsolute(size)
        error("text_extents requries font size be in absolute units")
    end
    return max_text_extents(font_family, size/pt, texts...)
end


# Return an array with the extents of each element
function text_extents(font_family::String, pts::Float64, texts::String...)
    pango_set_font(pangolayout::PangoLayout, font_family, pts)
    return [pango_text_extents(pangolayout::PangoLayout, text)
            for text in texts]
end


function text_extents(font_family::String, size::Measure, texts::String...)
    return text_extents(font_family, size/pt, texts...)
end


const pango_attrs = [
    (:PANGO_ATTR_LANGUAGE,        :PangoAttrLanguage),
    (:PANGO_ATTR_FAMILY,          :PangoAttrString),
    (:PANGO_ATTR_STYLE,           :PangoAttrInt),
    (:PANGO_ATTR_WEIGHT,          :PangoAttrInt),
    (:PANGO_ATTR_VARIANT,         :PangoAttrInt),
    (:PANGO_ATTR_STRETCH,         :PangoAttrInt),
    (:PANGO_ATTR_SIZE,            :PangoAttrSize),
    (:PANGO_ATTR_FONT_DESC,       :PangoAttrFontDesc),
    (:PANGO_ATTR_FOREGROUND,      :PangoAttrColor),
    (:PANGO_ATTR_BACKGROUND,      :PangoAttrColor),
    (:PANGO_ATTR_UNDERLINE,       :PangoAttrInt),
    (:PANGO_ATTR_STRIKETHROUGH,   :PangoAttrInt),
    (:PANGO_ATTR_RISE,            :PangoAttrInt),
    (:PANGO_ATTR_SHAPE,           :PangoAttrShape),
    (:PANGO_ATTR_SCALE,           :PangoAttrFloat),
    (:PANGO_ATTR_FALLBACK,        :PangoAttrFallback),
    (:PANGO_ATTR_LETTER_SPACING,  :PangoAttrInt),
    (:PANGO_ATTR_UNDERLINE_COLOR, :PangoAttrColor),
    (:PANGO_ATTR_ABSOLUTE_SIZE,   :PangoAttrSize),
    (:PANGO_ATTR_GRAVITY,         :PangoAttrInt),
    (:PANGO_ATTR_GRAVITY_HINT,    :PangoAttrInt)]


for (i, (attr, t)) in enumerate(pango_attrs)
    @eval begin
        const $attr = $i
    end
end


const PANGO_STYLE_NORMAL  = 0
const PANGO_STYLE_OBLIQUE = 1
const PANGO_STYLE_ITALIC  = 2


const PANGO_WEIGHT_THIN = 100
const PANGO_WEIGHT_ULTRALIGHT = 200
const PANGO_WEIGHT_LIGHT = 300
const PANGO_WEIGHT_BOOK = 380
const PANGO_WEIGHT_NORMAL = 400
const PANGO_WEIGHT_MEDIUM = 500
const PANGO_WEIGHT_SEMIBOLD = 600
const PANGO_WEIGHT_BOLD = 700
const PANGO_WEIGHT_ULTRABOLD = 800
const PANGO_WEIGHT_HEAVY = 900
const PANGO_WEIGHT_ULTRAHEAVY = 1000


# A Julia manifestation of a set of pango attributes
type PangoAttr
    rise::Maybe(Int)
    scale::Maybe(Float64)
    style::Maybe(Int)
    weight::Maybe(Int)

    function PangoAttr()
        new(nothing, nothing, nothing, nothing)
    end
end


function isempty(attr::PangoAttr)
    all([getfield(attr, name) === nothing for name in PangoAttr.names])
end


# Set an attribute in a PangoAttr
#
# Args:
#   attr: A PangoAttr to update.
#   attr_name: A pango attribute name (e.g., :PANGO_ATTR_RISE)
#   value: The value with which to update the attribute.
#
# Returns:
#   The attr.
function update_pango_attr(attr::PangoAttr, attr_name::Symbol, value)
    if attr_name == :PANGO_ATTR_RISE
        attr.rise = int64(value)
    elseif attr_name == :PANGO_ATTR_SCALE
        attr.scale = value
    elseif attr_name == :PANGO_ATTR_STYLE
        attr.style = int64(value)
    elseif attr_name == :PANGO_ATTR_WEIGHT
        attr.weight = int64(value)
    end
    attr
end


# Unpack the first part of a pango attribute
#
# Args:
#   ptr: A pointer to a PangoAttribute
#   t: The type of the attribute (e.g. PangoAttrInt)
#
# Returns:
#   A tuple of the form (start_idx, end_idx, value)
#
function unpack_pango_attr(ptr::Ptr{Void}, t::Symbol)
    ptr += sizeof(Ptr{Void}) # skip `klass` pointer
    ptr = convert(Ptr{Uint32}, ptr)
    idx = pointer_to_array(ptr, (2,))
    ptr += 2 * sizeof(Uint32)
    ptr = convert(Ptr{Void}, ptr)

    if t == :PangoAttrInt
        value = unpack_pango_int(ptr)
    elseif t == :PangoAttrFloat
        value = unpack_pango_float(ptr)
    else
        value = nothing
    end

    (idx[1], idx[2], value)
end


# Unpack a pango int attribute.
#
# Args:
#   ptr: A point to a PangoAttrInt plus sizeof(PangoAttribute)
#
# Returns:
#   And int value.
function unpack_pango_int(ptr::Ptr{Void})
    ptr = convert(Ptr{Int32}, ptr)
    pointer_to_array(ptr, (1,))[1]
end


function unpack_pango_float(ptr::Ptr{Void})
    ptr = convert(Ptr{Float64}, ptr)
    pointer_to_array(ptr, (1,))[1]
end


#function unpack_pango_size(ptr::Ptr{Void})
    #ptr = convert(Ptr{Int32}, ptr)
    #size = point_to_array(ptr, (1,))[1]
    #ptr = convert(Ptr{Uint32}, ptr)
    #absolute = point_to_array(ptr, (1,))[1] & 0x1

    #println(size, absolute)
    #nothing
#end


# TODO: unpacking other attributes

# Unpack a list of pango attributes
#
# Args:
#   ptr: A pointer to a PangoAttrList
#
# Returns:
#   A list of the form [(start_idx, attribute), ...] in which the start_idx
#   values are increasing and the attribute is a set of attributes that
#   should be applied starting at that position.
#
function unpack_pango_attr_list(ptr::Ptr{Void})
    attr_it = ccall((:pango_attr_list_get_iterator, libpango),
                    Ptr{Void}, (Ptr{Void},), ptr)

    # Alias some ugly C calls.
    attr_it_next = () -> ccall((:pango_attr_iterator_next, libpango),
                               Int32, (Ptr{Void},), attr_it)

    attr_it_get = attr_name -> ccall((:pango_attr_iterator_get, libpango),
                                     Ptr{Void}, (Ptr{Void}, Int32),
                                     attr_it, eval(attr_name))

    attr_it_range = () -> begin
        start_idx = Array(Int32, 1)
        end_idx = Array(Int32, 1)
        ccall((:pango_attr_iterator_range, libpango),
              Void, (Ptr{Void}, Ptr{Int32}, Ptr{Int32}),
              attr_it, start_idx, end_idx)
        (start_idx[1], end_idx[1])
    end


    attrs = Array((Int, PangoAttr), 0)

    while attr_it_next() != 0

        attr = PangoAttr()
        local start_idx

        for (attr_name, attr_type) in pango_attrs
            c_attr = attr_it_get(attr_name)
            (start_idx, end_idx) = attr_it_range()

            if c_attr != C_NULL
                (_, _, value) = unpack_pango_attr(c_attr, attr_type)
                update_pango_attr(attr, attr_name, value)
            end
        end

        push!(attrs, (start_idx, attr))
    end

    ccall((:pango_attr_iterator_destroy, libpango),
          Void, (Ptr{Void},), attr_it)

  attrs
end


function pango_to_svg(text::String)
    c_stripped_text = Array(Ptr{Uint8}, 1)
    c_attr_list = Array(Ptr{Void}, 1)

    ret = ccall((:pango_parse_markup, libpango),
                Int32, (Ptr{Uint8}, Int32, Uint32, Ptr{Ptr{Void}},
                        Ptr{Ptr{Uint8}}, Ptr{Uint32}, Ptr{Void}),
                bytestring(text), -1, 0, c_attr_list, c_stripped_text,
                C_NULL, C_NULL)

    if ret == 0
        error("Could not parse pango markup.")
    end

    # TODO: do c_stripped_text and c_attr_list need to be freed?

    bytearray =  str -> convert(Array{Uint8, 1}, str)

    text = bytearray(bytestring(c_stripped_text[1]))

    last_idx = 1
    open_tag = false
    tagged_text = sprint() do io
        for (idx, attr) in unpack_pango_attr_list(c_attr_list[1])
            write(io, text[last_idx:idx])
            last_idx = idx + 1

            if open_tag
                write(io, "</tspan>")
            end

            if isempty(attr)
                open_tag = false
                continue
            end

            open_tag = true

            write(io, "<tspan style=\"dominant-baseline:inherit\"")

            # "baseline-shift" is not currently supported Firefox or IE.
            # if !(attr.rise === nothing)
            #     @printf(io, " baseline-shift=\"%s\"",
            #             fmt_float(((attr.rise / PANGO_SCALE)pt).abs))
            # end

            if !(attr.rise === nothing)
                @printf(io, " dy=\"%s\"",
                        pango_fmt_float(-((attr.rise / PANGO_SCALE)pt).abs))
            end

            if !(attr.scale === nothing)
                @printf(io, " font-size=\"%s%%\"",
                        pango_fmt_float(100.0 * attr.scale))
            end

            if !(attr.style === nothing)
                if attr.style == PANGO_STYLE_NORMAL
                    @printf(io, " font-style=\"%s\"", "normal")
                elseif attr.style == PANGO_STYLE_OBLIQUE
                    @printf(io, " font-style=\"%s\"", "oblique")
                elseif attr.style == PANGO_STYLE_ITALIC
                    @printf(io, " font-style=\"%s\"", "italic")
                end
            end

            if !(attr.weight === nothing)
                @printf(io, " font-weight=\"%d\"", attr.weight)
            end

            write(io, ">")
        end

        write(io, text[last_idx:end])
    end

    tagged_text
end
