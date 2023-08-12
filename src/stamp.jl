# Juliafication of stamp.capnp

"""
A "postage stamp" of data extracted from a larger set of raw data.
This data has been upchannelized with an FFT but is still multi-antenna
complex voltages.
"""
struct Stamp
  """
  The seticore version that generated this data.     
  """
  seticoreVersion::String

  """
  Source of the boresight target.
  """
  sourceName::String
  """
  RA of the boresight target (hours).
  """
  ra::Float64
  """
  Declination of the boresight target (degrees).
  """
  dec::Float64

  # Other standard metadata found in FBH5 files.
  # This metadata applies specifically to the postage stamp itself, not the larger
  # file we extracted it from.
  fch1::Float64
  foff::Float64
  tstart::Float64
  tsamp::Float64
  telescopeId::Int32
 
  # Metadata describing how exactly we extracted this stamp.

  """
  The coarse channel in the original file that we extracted data from.
  Matches coarseChannel in the hit.

  !!! note
      Currently zero based!
  """
  coarseChannel::Int32

  """
  The size of FFT we used to create fine channels.
  """
  fftSize::Int32

  """
  The first post-FFT channel that we extracted.  So the first column in `data`
  corresponds to this column in the original post-FFT data.  This will not
  exactly match startChannel in a hit, because we combine adjacent hits and may
  use different window sizes. But if you consider the intervals [startChannel,
  startChannel + numChannels), the interval for the stamp should overlap with
  the interval for any relevant hits.

  !!! note
      Currently zero based!
  """
  startChannel::Int32

  """
  Metadata for the best hit we found for this stamp.
  Not populated for stamps extracted with the `seticore` CLI tool.
  """
  signal::Signal

  """
  Where the raw file starts in the complete input band (e.g. in the beamforming
  recipe).  Metadata copied from the input RAW file.  Needed to match up this
  stamp to the beamforming recipe file.
  """
  schan::Int32

  """
  `OBSID` (OBServation ID) field from the input RAW file.  Metadata copied from
  the input raw file.  Needed to match up this stamp to the beamforming recipe
  file.
  """
  obsid::String

  # Dimensions of the data
  numTimesteps::Int32
  numChannels::Int32
  numPolarizations::Int32
  numAntennas::Int32
 
  """
  An array of complex voltages.
  Indexed as `[antenna, polarization, channel, time]`
  """
  data::Array{Complex{Float32}, 4}
end

"""
    Stamp(s)
Construct a `Stamp` from capnp object `s`.
"""
function Stamp(s)
    ntime = convert(Int32, s.numTimesteps)
    nchan = convert(Int32, s.numChannels)
    npol  = convert(Int32, s.numPolarizations)
    nant  = convert(Int32, s.numAntennas)
    datavec = convert(Vector{Float32}, s.data)
    datavecz = reinterpret(Complex{Float32}, datavec)
    data = reshape(datavecz, Int64(nant), Int64(npol), Int64(nchan), Int64(ntime))

    Stamp(
        convert(String,  s.seticoreVersion),
        convert(String,  s.sourceName),
        convert(Float64, s.ra),
        convert(Float64, s.dec),
        convert(Float64, s.fch1),
        convert(Float64, s.foff),
        convert(Float64, s.tstart),
        convert(Float64, s.tsamp),
        convert(Int32,   s.telescopeId),
        convert(Int32,   s.coarseChannel),
        convert(Int32,   s.fftSize),
        convert(Int32,   s.startChannel),
        Signal(s.signal),
        convert(Int32,   s.schan),
        convert(String,  s.obsid),
        ntime,
        nchan,
        npol,
        nant,
        data
    )
end

"""
    Stamp(d::AbstractDict, data::Array)

Construct a `Stamp` from `AbstractDict` object `d`, whose key type must be
`Symbol` or an `AbstractString`, and `data`.
"""
function Stamp(d::AbstractDict{T,Any}, data::Array{Float32}) where T<:Union{AbstractString,Symbol}
    Stamp(
        # Maybe these converts are not needed?
        convert(String,  d[T(:seticoreVersion)]),
        convert(String,  d[T(:sourceName)]),
        convert(Float64, d[T(:ra)]),
        convert(Float64, d[T(:dec)]),
        convert(Float64, d[T(:fch1)]),
        convert(Float64, d[T(:foff)]),
        convert(Float64, d[T(:tstart)]),
        convert(Float64, d[T(:tsamp)]),
        convert(Int32,   d[T(:telescopeId)]),
        convert(Int32,   d[T(:coarseChannel)]),
        convert(Int32,   d[T(:fftSize)]),
        convert(Int32,   d[T(:startChannel)]),
        Signal(d),
        convert(Int32,   d[T(:schan)]),
        convert(String,  d[T(:obsid)]),
        convert(Int32,   d[T(:numTimesteps)]),
        convert(Int32,   d[T(:numChannels)]),
        convert(Int32,   d[T(:numPolarizations)]),
        convert(Int32,   d[T(:numAntennas)]),
        data
    )
end

function getdata(s::Stamp)
    s.data
end

const StampDictFields = (
    :seticoreVersion,
    :sourceName,
    :ra,
    :dec,
    :fch1,
    :foff,
    :tstart,
    :tsamp,
    :telescopeId,
    :coarseChannel,
    :fftSize,
    :startChannel,
    :schan,
    :obsid,
    :numTimesteps,
    :numChannels,
    :numPolarizations,
    :numAntennas
)

function OrderedCollections.OrderedDict{Symbol,Any}(s::Stamp)
    d = OrderedDict{Symbol,Any}(
        StampDictFields .=> getfield.(Ref(s), StampDictFields)
    )
    merge!(d, OrderedDict(s.signal))
end

function OrderedCollections.OrderedDict(s::Stamp)
    OrderedCollections.OrderedDict{Symbol,Any}(s)
end

"""
    load_stamp(filename, offset; kwargs...) -> OrderedDict, Array{ComplexF32,4}
    load_stamp(io::IO[, offset]; kwargs...) -> OrderedDict, Array{ComplexF32,4}

Load a single `Stamp` from the given `offset` (or current position) within
`filename` or `io` and return the metadata fields as an
`OrderedDict{Symbol,Any}` and the complex voltage data of the stamp as an
`Array{ComplexF32,4}`.  For consistency with `load_hits`, the metadat includes a
`:fileoffset` entry whose value is `offset`.

The only supported `kwargs` is `traversal_limit_in_words` which sets the
maximmum size of a stamp.  It default it 2^30 words.
"""
function load_stamp(io::IO; traversal_limit_in_words=2^30)
    offset = lseek(io)
    stamp = Stamp(SeticoreCapnp.CapnpStamp[].Stamp.read(io; traversal_limit_in_words))
    data = getdata(stamp)

    meta = OrderedDict(stamp)
    # Merge the Signal fields as additional columns, omitting redundant
    # `coarseChannel` field (and already omitted `numTimesteps` field).
    sig = OrderedDict(stamp.signal)
    delete!(sig, :coarseChannel)
    merge!(meta, sig)
    # Add file offsets
    meta[:fileoffset] = offset

    meta, data
end

function load_stamp(io::IO, offset; traversal_limit_in_words=2^30)
    seek(io, offset)
    load_stamp(io; traversal_limit_in_words)
end

function load_stamp(stamps_filename, offset; traversal_limit_in_words=2^30)
    open(stamps_filename) do io
        load_stamp(io, offset; traversal_limit_in_words)
    end
end

"""
    foreach_stamp(f, filename; kwargs...)

For each `Stamp` in the given `filename`, call `f` passing 
`OrderedDict{Symbol,Any}` metadata the `Array{ComplexF32,4}` voltage data.  The
metadat includes a `:fileoffset` entry whose value is the offset of the `Stamp`
within the input file. This offset can be used with `load_stamp` if desired.

The only supported `kwargs` is `traversal_limit_in_words` which sets the
maximmum size of a hit.  It default it 2^30 words.
"""
function foreach_stamp(f, stamps_filename; traversal_limit_in_words=2^30)
    # TODO Make this into a proper Julia iterator
    n = filesize(stamps_filename)
    open(stamps_filename) do io
        while lseek(io) < n
            m, d = load_stamp(io; traversal_limit_in_words)
            f(m, d)
            # Break if io's fd did not advance (should "never" happen)
            # (avoids pathological infinite loop)
            lseek(io) == m[:fileoffset] && break
        end
    end
    nothing
end

"""
    load_stamps(filename; kwargs...) -> Vector{OrderedDict}, Vector{Array{Float32,4}}

Load the `Stamp`s from the given `filename` and return the metadata fields as a
`Vector{OrderedDict{Symbol,Any}}` and the voltage data as a
`Vector{Array{ComplexF32,4}}` whose elements correspond one-to-one with the
entries of the metadata `Vector`.  The metadata entries includes a `:fileoffset`
entry whose value is the offset of the `Stamp` within the input file. This
offset can be used with `load_stamp` if desired.

The only supported `kwargs` is `traversal_limit_in_words` which sets the
maximmum size of a stamp.  It default it 2^30 words.
"""
function load_stamps(stamps_filename; traversal_limit_in_words=2^30)
    meta = OrderedDict{Symbol,Any}[]
    data = Array{ComplexF32}[]
    foreach_stamp(stamps_filename; traversal_limit_in_words) do m,d
        push!(meta, m)
        push!(data, d)
    end

    meta, data
end
