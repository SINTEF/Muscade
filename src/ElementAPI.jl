abstract type AbstractElement  end

# MUST be used by elements to unpack X and U.  Today, the various derivatives are packed into tuples.  Would we use Adiff tomorrow, allowing
# correct computation of e.g. Coriolis terms in beam elements?
∂n(Y,n) = n+1≤lastindex(Y) ? Y[n+1] : zeros(eltype(Y[1]),size(Y[1])...)  # this implementation will be slow if zero is to be returned!
∂0(y)  = ∂n(y,0)
∂1(y)  = ∂n(y,1)
∂2(y)  = ∂n(y,2)

draw(axe,key,out, ::E,args...;kwargs...) where{E<:AbstractElement}    = nothing # by default, an element draws nothing

espyable(    ::Type{E}) where{E<:AbstractElement}  = (;)
request2draw(::Type{E}) where{E<:AbstractElement}  = (;)
doflist(     ::Type{E}) where{E<:AbstractElement}  = muscadeerror(@sprintf("method 'Muscade.doflist' must be provided for elements of type '%s'\n",E))
### Not part of element API, not exported by Muscade

getnnod(E::DataType)              = maximum(doflist(E).inod) 
getdoflist(E::DataType)           = doflist(E).inod, doflist(E).class, doflist(E).field
getidof(E::DataType,class)        = findall(doflist(E).class.==class)  
getndof(E::DataType)              = length(doflist(E).inod)
getndof(E::DataType,class)        = length(getidof(E,class))  
getndof(E::DataType,class::Tuple) = ntuple(i->getndof(E,class[i]),length(class))

####### Lagrangian from residual and residual from Lagrangian
@generated function implemented(eleobj) 
    r = hasmethod(residual  ,(eleobj,   NTuple,NTuple,𝕣1,𝕣,𝕣,NamedTuple))
    l = hasmethod(lagrangian,(eleobj,𝕣1,NTuple,NTuple,𝕣1,𝕣,𝕣,NamedTuple))
    return :(Val{$r},Val{$l})
end

# if residual or lagrange outputs just one vector or number, this element does not implementinequality constraints, so append α=0.
defα(x::Union{Number,AbstractVector})               = x,∞
defα(x::Tuple)                                      = x

getresidual(          ::Type{<:Val}     ,::Type{<:Val}     ,out,key,eleobj::AbstractElement,args...) = 
            muscadeerror(args[end],@sprintf("No method 'Muscade.lagrangian(out,key,eleobj,δX,X,U,A, t,γ,dbg)' or 'Muscade.residual(out,key,eleobj,X,U,A, t,γ,dbg)' for elements of type '%s'",typeof(eleobj)))
getlagrangian(        ::Type{<:Val}     ,::Type{<:Val}     ,out,key,eleobj::AbstractElement,args...) = 
            muscadeerror(args[end],@sprintf("No method 'Muscade.lagrangian(out,key,eleobj,δX,X,U,A, t,γ,dbg)' or 'Muscade.residual(out,key,eleobj,X,U,A, t,γ,dbg)' for elements of type '%s'",typeof(eleobj)))
getresidual(          ::Type{<:Val}     ,::Type{<:Val}     ,eleobj::AbstractElement,args...) = 
            muscadeerror(args[end],@sprintf("No method 'Muscade.lagrangian(eleobj,δX,X,U,A, t,γ,dbg)' or 'Muscade.residual(eleobj,X,U,A, t,γ,dbg)' for elements of type '%s'",typeof(eleobj)))
getlagrangian(        ::Type{<:Val}     ,::Type{<:Val}     ,eleobj::AbstractElement,args...) = 
            muscadeerror(args[end],@sprintf("No method 'Muscade.lagrangian(eleobj,δX,X,U,A, t,γ,dbg)' or 'Muscade.residual(eleobj,X,U,A, t,γ,dbg)' for elements of type '%s'",typeof(eleobj)))

# Go straight
getresidual(          ::Type{Val{true}} ,::Type{<:Val}             ,eleobj::AbstractElement,args...) = defα(residual(          eleobj,args...))
getresidual(          ::Type{Val{true}} ,::Type{<:Val}     ,out,key,eleobj::AbstractElement,args...) = defα(residual(  out,key,eleobj,args...))
getlagrangian(        ::Type{<:Val}     ,::Type{Val{true}}         ,eleobj::AbstractElement,args...) = defα(lagrangian(        eleobj,args...))
getlagrangian(        ::Type{<:Val}     ,::Type{Val{true}} ,out,key,eleobj::AbstractElement,args...) = defα(lagrangian(out,key,eleobj,args...))

# Swap
# TODO merge the function pairs into one with Julia 1.9
function getresidual(  ::Type{Val{false}},::Type{Val{true}} ,eleobj::AbstractElement, X,U,A, t,γ,dbg)  
    P   = constants(∂0(X),∂0(U),A,t)
    Nx  = length(∂0(X))
    δX  = δ{P,Nx,𝕣}()   
    L,α = defα(lagrangian(eleobj,δX,X,U,A, t,γ,dbg))
    return ∂{P,Nx}(L),α
end
function getresidual(::Type{Val{false}},::Type{Val{true}} ,out,key,eleobj::AbstractElement,X,U,A, t,γ,dbg)  
    P   = constants(∂0(X),∂0(U),A,t)
    Nx  = length(∂0(X))
    δX  = δ{P,Nx,𝕣}()   
    L,α = defα(lagrangian(out,key,eleobj,δX,X,U,A, t,γ,dbg))
    return ∂{P,Nx}(L),α
end
function getlagrangian(::Type{Val{true}} ,::Type{Val{false}},eleobj::AbstractElement,δX,X,U,A, t,γ,dbg) 
    R,α = defα(residual(eleobj,X,U,A, t,γ,dbg))
    return δX ∘₁ R , α
end
function getlagrangian(::Type{Val{true}} ,::Type{Val{false}},out,key,eleobj::AbstractElement,δX,X,U,A, t,γ,dbg) 
    R,α = defα(residual(out,key,eleobj,X,U,A, t,γ,dbg))
    return δX ∘₁ R , α
end

###### scaled functions

function scaledlagrangian(scale,eleobj::AbstractElement,Λs,Xs::NTuple{Nxder},Us::NTuple{Nuder},As, t,γ,dbg) where{Nxder,Nuder}
    Λ     =       Λs.*scale.Λ                 
    X     = NTuple{Nxder}(xs.*scale.X for xs∈Xs)  
    U     = NTuple{Nuder}(us.*scale.U for us∈Us)
    A     =       As.*scale.A
    L,α   = getlagrangian(implemented(eleobj)...,eleobj,Λ,X,U,A, t,γ,dbg)
    hasnan(L) && muscadeerror((dbg...,eletype=E),"NaN in a Lagrangian or its partial derivatives")
    return L,α
end    
function scaledresidual(scale,eleobj::AbstractElement, Xs::NTuple{Nxder},Us::NTuple{Nuder},As, t,γ,dbg) where{Nxder,Nuder} 
    X     = NTuple{Nxder}(xs.*scale.X for xs∈Xs)  
    U     = NTuple{Nuder}(us.*scale.U for us∈Us)
    A     =       As.*scale.A
    R,α   = getresidual(implemented(eleobj)...,eleobj, X,U,A, t,γ,dbg) 
    hasnan(R) && muscadeerror(dbg,"NaN in a residual or its partial derivatives")
    return R.*scale.Λ ,α
end
