"""
 An implementation of univariate Laurent polynomials.
 A Pol contains two fields: its vector of coefficients, and its valuation.

# Examples
```julia-repl
julia> Pol([1,2],0) # coefficients should have no leading or trailing zeroes.
1+2x

julia> Pol([1,2],-1)
x^-1+2

julia> valuation(ans)
-1

julia> Pols.varname(:q) # change string used for printing and set variable q
:q

julia> p=(q+1)^2
1+2q+q^2

julia> degree(p)
2

julia> value(p,1//2)
9//4

julia> divrem(q^3+1,q+2) # changes coefficients to field elements
(4.0-2.0q+1.0q^2, -7.0)

julia> divrem1(q^3+1,q+2) # keeps the ring, but needs second argument unitary
(4-2q+q^2, -7)

julia> cyclotomic_polynomial(24) # the 24-th cyclotomic polynomial
1-q^4+q^8

```

see also the individual documentation of gcd.
"""
module Pols
export Pol, valuation, value, cyclotomic_polynomial, divrem1
using Memoize, Reexport
@reexport using ..Util

const var=[:x]
function varname(a::Symbol)
  var[1]=a
end

struct Pol{T}
  c::Vector{T}
  v::Int
end

function Polstrip(v::AbstractVector,val=0)
  b=findfirst(x->!iszero(x),v)
  if b==nothing return Pol(eltype(v)[],0) end
  l=findlast(x->!iszero(x),v)
  Pol(v[b:l],val+b-1)
end

function Pol(a)
  if iszero(a) Pol(typeof(a)[],0) end
  Pol([a],0)
end

function Pol(t::Symbol)
  varname(t)
  Base.eval(Main,:($t=Pol([1],1)))
end

Base.copy(p::Pol)=Pol(p.c,p.v)
#Base.convert(::Type{Pol},a::Pol)=a

Util.degree(p::Pol)=length(p.c)-1+p.v

valuation(p::Pol)=p.v

value(p::Pol,x)=horner(x,p.c)*x^p.v

Base.:(==)(a::Pol, b::Pol)= a.c==b.c && a.v==b.v

Base.one(a::Pol)=Pol([one(eltype(a.c))],0)
Base.one(::Type{Pol{T}}) where T=Pol([one(T)],0)
Base.zero(a::Pol)=Pol(empty(a.c),0)
Base.iszero(a::Pol)=length(a.c)==0
Base.transpose(a::Pol)=a

function Base.show(io::IO,p::Pol)
  s=join(map(eachindex(p.c))do i
    c=p.c[i]
    if iszero(c) return "" end
    deg=i+p.v-1
    mon=deg==0 ? "1" : String(var[1])*(deg==1 ? "" : "^$deg")
#   if c isa Rational && denominator(c)==1 c=repr(Int(c))
#   else
      c=repr(c)
#   end
    if occursin(r"[+\-*/]",c[2:end]) c="($c)" end
    if deg==0 res=c
    else res=(c=="1" ? "" : (c=="-1" ? "-" : c))*mon
    end
    if res[1]!='-' res="+"*res end
    res
  end)
  if s=="" print(io,"0")
  elseif  s[1]=='+' print(io,s[2:end])
  else print(io,s) end
end

function Base.:*(a::Pol{T}, b::Pol{T})where T
  if iszero(a) || iszero(b) return zero(a) end
  res=map(1:length(a.c)+length(b.c)-1)do i
@inbounds sum(j->a.c[j]*b.c[i+1-j],max(1,i-length(b.c)+1):min(i,length(a.c)))
  end
  Pol(res,a.v+b.v)
end

Base.:*(a::Pol, b::T) where T=iszero(b) ? zero(a) : Pol(a.c.*b,a.v)
Base.:*(b::T, a::Pol) where T=iszero(b) ? zero(a) : Pol(a.c.*b,a.v)

Base.:^(a::Pol, n::Integer)= n>=0 ? Base.power_by_squaring(a,n) :
                              Base.power_by_squaring(inv(a),-n)

function Base.:+(a::Pol{T1}, b::Pol{T2})where T1 where T2
  d=b.v-a.v
  if d<0 return b+a end
  T=promote_type(T1,T2)
  c=zeros(T,max(length(a.c),d+length(b.c)))
@inbounds  c[eachindex(a.c)].=a.c
@inbounds  c[d.+eachindex(b.c)].+=b.c
  Polstrip(c,a.v)
end

Base.:+(a::Pol, b::T) where T=a+Pol(b)
Base.:+(b::T, a::Pol) where T=Pol(b)+a

Base.:-(a::Pol)=Pol(-a.c,a.v)
Base.:-(a::Pol, b::Pol)=a+(-b)
Base.:-(a::Pol, b::T) where T=a-Pol(b)
Base.:-(b::T, a::Pol) where T=Pol(b)-a

"""
computes (p,q) such that a=p*b+q
"""
function Base.divrem(a::Pol, b::Pol)
  d=inv(b.c[end])
  T=typeof(a.c[end]*d)
  v=T.(a.c)
  res=T[]
  for i=length(a.c):-1:length(b.c)
    if iszero(v[i]) c=zero(d)
    else c=v[i]*d
         v[i-length(b.c)+1:i] .-= c .* b.c
    end
    pushfirst!(res,c)
  end
  Pol(res,a.v-b.v),Polstrip(v,a.v)
end

"""
divrem when b unitary: does not change type
"""
function divrem1(a::Pol{T1}, b::Pol{T2})where T1 where T2
  d=b.c[end]
  if d^2!=1 throw(InexactError) end
  T=promote_type(T1,T2)
  v=T.(a.c)
  res=T[]
  for i=length(a.c):-1:length(b.c)
    if iszero(v[i]) c=zero(d)
    else c=v[i]*d
         v[i-length(b.c)+1:i] .-= c .* b.c
    end
    pushfirst!(res,c)
  end
  Pol(res,a.v-b.v),Polstrip(v,a.v)
end

Base.:/(p::Pol,q::T) where T=Pol(p.c/q,p.v)

"""
  gcd(p::Pol, q::Pol)
  the coefficients of p and q must be elements of a field for
  gcd to be type-stable

# Examples
```julia-repl
julia> gcd(q+1,q^2-1)
1.0+1.0q

julia> gcd(q+1//1,q^2-1//1)
1+q
```
"""
function Base.gcd(p::Pol,q::Pol)
  while !iszero(q)
    q=q/q.c[end]
    (q,p)=(divrem(p,q)[2],q)
  end
  return p/p.c[end]
end

function Base.inv(p::Pol)
  if length(p.c)>1 || !(p.c[1]^2==1) Throw(InexactError()) end
  Pol([p.c[1]],-p.v)
end

@memoize function cyclotomic_polynomial(n::Integer)
  v=fill(0,n+1);v[1]=-1;v[n+1]=1;res=Pol(v,0)
  for d in divisors(n)
    if d!=n
      res,foo=divrem1(res,cyclotomic_polynomial(d))
    end
  end
  res
end
end
