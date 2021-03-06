"""
This module is a port of some GAP functionality on permutation groups.

See Holt "Handbook of computational group theory" chap. 4 for basic algorithms.

The  only  field  of  a  PermGroup  G  at  the  start  is gens, the list of
generators  of G.  To mimic  GAP records  where attributes/properties of an
object  are computed on demand when asked for, other fields are computed on
demand  and stored in the  field prop of the  PermGroup, which starts as an
empty dict.

# Examples
```julia-repl
julia> G=PermGroup([Perm(i,i+1) for i in 1:2])
PermGroup((1,2),(2,3))

julia> collect(G)  # PermGroups are iterators over their elements
6-element Array{Perm{Int64},1}:
 (1,2)
 (1,3,2)
 ()
 (1,2,3)
 (1,3)
 (2,3)

julia> degree(G)  # maximum degree of an element of G
3

julia> orbit(G,1) # orbit of point 1 under G
3-element Array{Int64,1}:
 1
 2
 3

# orbit decorated with representatives moving 1 to given point
julia> orbit_and_representative(G,1)
Dict{Int64,Perm{Int64}} with 3 entries:
  2 => (1,2)
  3 => (1,3,2)
  1 => ()

julia> Perm(1,2) in G
true

julia> Perm(1,2,4) in G
false

#Elements,  appartenance test  and other  function are  computed on  G using
#Schreier-Sims theory, that is computing the following

julia> base(G) # a list of points that no element of G fixes
2-element Array{Int64,1}:
 1
 2

julia> centralizers(G) # the i-th element is the centralizer of base[1:i-1]
2-element Array{PermGroup{Int64},1}:
 PermGroup((1,2),(2,3))
 PermGroup((2,3))

# i-th element is orbit_and_representive of centralizer[i] on base[i]
julia> centralizer_orbits(G)
2-element Array{Dict{Int64,Perm{Int64}},1}:
 Dict(2=>(1,2),3=>(1,3,2),1=>())
 Dict(2=>(),3=>(2,3))

julia> words(G)  # minimal word for each element of G
6-element Array{Array{Int64,1},1}:
 []
 [2]
 [1]
 [2, 1]
 [1, 2]
 [1, 2, 1]

julia> elements(G) # elements in the same order as words
6-element Array{Perm{Int64},1}:
 ()
 (2,3)
 (1,2)
 (1,2,3)
 (1,3,2)
 (1,3)

# finally, benchmarks
julia> @btime collect(symmetric_group(8));
  10.252 ms (350529 allocations: 14.17 MiB)

julia> @btime words(symmetric_group(8));
  111.824 ms (1596449 allocations: 38.64 MiB)
```
"""
module PermGroups
using ..Perms
export PermGroup, orbit, orbit_and_representative, elements, words,
  symmetric_group, base, centralizer_orbits, centralizers, elts_and_words

struct PermGroup{T}
  gens::Vector{Perm{T}}
  prop::Dict{Symbol,Any}
end

function Base.one(G::PermGroup{T})where T
  Perm{T}()
end

gens(G::PermGroup)=G.gens

function PermGroup(a::Vector{Perm{T}})where T
  PermGroup(a,Dict{Symbol,Any}())
end

function Base.show(io::IO,G::PermGroup)
  print(io,"PermGroup($(join(map(repr,G.gens),',')))")
end

using ..Util
function Util.degree(G::PermGroup)::Int
  gets(G,:degree)do G maximum(map(largest_moved_point,gens(G))) end
end

" The symmetric group of degree n "
function symmetric_group(n::Int)
  PermGroup([Perm(i,i+1) for i in 1:n-1])
end

" orbit(G,p) is the orbit of point p under PermGroup G"
function orbit(G::PermGroup{T},p::T)where T
  res=BitSet()
  new=BitSet(p)
  while true
    union!(res,new)
    n=vec([p^s for p in new, s in gens(G)])
    new=BitSet(setdiff(n,res))
    if isempty(new) break end
  end
  collect(res)
end

" describe the orbit of p as a Schreier vector "
function schreier_vector(G::PermGroup,p)
  res=zeros(Int,degree(G))
  res[p]=-1
  new=BitSet([p])
  while true
    n=new
    new=BitSet([])
    for p in n, i in eachindex(G.gens)
      q=p^(G.gens[i])
      if res[q]==0
        res[q]=i
        push!(new,q)
      end
    end
    if isempty(new) break end
  end
  res
end

"returns Dict x=>g where x runs over orbit(G,p) and g is such that x=p^g"
function orbit_and_representative(G::PermGroup,p)
  new=[p]
  d=Dict(p=>one(G))
  while !isempty(new)
    old=copy(new)
    resize!(new,0)
    for s in G.gens, i in old
      let s=s,i=i,e=i^s
        get!(d,e) do
          push!(new,e)
          d[i]*s
        end
      end
    end
  end
  d
end

"""
 The input is
 -  g: an element of a PermGroup G
 -  B: a base (or partial base) of G
 -  Δ: Δ[i] is the orbit of C_G(B[1:i-1]) on B[i]
 The function returns g "stripped" of its components in all C_G(B[1:i])
"""
function strip(g::Perm{T},B::Vector{T},Δ::Vector{Dict{T,Perm{T}}}) where T
  h=g
  for i in eachindex(B)
    β=B[i]^h
    if !haskey(Δ[i],β)
      return h,i
    end
    h*=inv(Δ[i][β])
  end
  h,length(B)+1
end

"""
  see Holt, 4.4.2

  This function creates in G.prop the fields base, centralizers,
  centralizer_orbits. See the description in the functions with the same name.
"""
function schreier_sims(G::PermGroup{T})where T
  B=T[]
  S=Vector{Perm{T}}[]
  for x in gens(G)
    j=1
    while j<=length(B)
      push!(S[j],x)
      if B[j]^x!=B[j] break end
      j+=1
    end
    if j>length(B)
      push!(B,smallest_moved_point(x))
      push!(S,[x])
    end
  end
  H=[PermGroup(s) for s in S]
  Δ=map(orbit_and_representative,H,B)
  rep(v)=join(map(repr,v),',')
  i=length(B)
  while i>=1
   for β in keys(Δ[i]), x in S[i]
     h=Δ[i][β]* x *inv(Δ[i][β^x])
     if !isone(h)
       y=true
       h,j=strip(h,B,Δ)
       if j<=length(B)
         y=false
       elseif !isone(h)
         y=false
         push!(B,smallest_moved_point(h))
         push!(S,Perm{T}[])
       end
       if y==false
         for l in i+1:j
           push!(S[l],h)
           if l>length(H)
            push!(H,PermGroup(S[l]))
            push!(Δ,orbit_and_representative(H[l],B[l]))
           else
           H[l]=PermGroup(S[l])
           Δ[l]=orbit_and_representative(H[l],B[l])
           end
         end
         i=j
         @goto nexti
       end
     end
   end
   i-=1
   @label nexti
  end
  G.prop[:base]=B
  G.prop[:centralizers]=H
  G.prop[:centralizer_orbits]=Δ
end

" centralizers: the i-th element is the centralizer of base[1:i-1]"
function centralizers(G::PermGroup{T})::Vector{PermGroup{T}} where T
  getp(schreier_sims,G,:centralizers)
end

"""
  The  i-th element  is  a description of  the orbit of :centralizers[i] on
  :base[i]  as a Dict where each point q is the key to a permutation p such
  that :base[i]^p=q
"""
function centralizer_orbits(G::PermGroup{T})::Vector{Dict{T,Perm{T}}} where T
  getp(schreier_sims,G,:centralizer_orbits)
end

" A list of points stabilized by no element of G "
function base(G::PermGroup{T})::Vector{T} where T
  getp(schreier_sims,G,:base)
end

" length(G::PermGroup) returns the cardinality of G "
function Base.length(G::PermGroup)::Int
  gets(G,:length)do G prod(length,centralizer_orbits(G)) end
end

" Tells whether permutation g is an element of G "
function Base.in(g::Perm,G::PermGroup)
  g,i=strip(g,base(G),centralizer_orbits(G))
  isone(g)
end

function Base.iterate(G::PermGroup{T})where T
  prod=one(G)
  ll=values.(centralizer_orbits(G))
  state=map(reverse(ll)) do l
    u=iterate(l)
    if u==nothing  return nothing end
    prod*=u[1]::Perm{T}
    (prod,u[2]::Int)
  end
  prod::Perm{T},reverse(state)
end

function Base.iterate(G::PermGroup{T},state)where T
 for i in eachindex(state)
    u=iterate(values(centralizer_orbits(G)[i]),state[i][2])
    if u==nothing continue end
    if i==length(state)
      state[i]=u
    else
      state[i]=(state[i+1][1]*u[1],u[2])
    end
    for j in i-1:-1:1
      u=iterate(values(centralizer_orbits(G)[j]))
      state[j]=(state[j+1][1]*u[1],u[2])
    end
    return state[1][1],state
  end
  return nothing
end

Base.eltype(::Type{PermGroup{T}}) where T=Perm{T}

" This function creates the fields :elements and :words "
function elts_and_words(G::PermGroup{T})where T
  elements=[one(G)]
  words=[T[]]
  for i in eachindex(gens(G))
    reps = [one(G)]
    wds = [T[]]
    nelms=copy(elements)
    nwords=copy(words)
    j=1
    while j<=length(reps)
      for k in 1:i
        e=reps[j]*gens(G)[k]
        we = vcat(wds[j],[k])
        if !(e in nelms)
          push!( reps, e )
          push!( wds, we )
          append!( nelms, elements .* Ref(e))
          append!( nwords, map(x->vcat(x,we),words) )
        end
      end
      j+=1
    end
    elements = nelms
    words = nwords
#   print("#I WordsGroup:|<elements>|=",length(elements),", $i.th generator\r")
  end
  e=sort(eachindex(elements),by=x->elements[x])
# print( "#I  WordsGroup: |elements| = ", length( elements ), "\n" )
  G.prop[:elements]=elements[e]
  G.prop[:words]=words[e]
end

" List of minimal words in the generators elements(G) "
function words(G::PermGroup{T})::Vector{Vector{T}} where T
  getp(elts_and_words,G,:words)
end

" The list of elements of G in the same order as words"
function elements(G::PermGroup{T})::Vector{Perm{T}} where T
  getp(elts_and_words,G,:elements)
end

end
