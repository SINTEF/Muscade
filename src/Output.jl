

"""
    et = eletyp(model)

Return a vector of the concrete types of elements in the model. 
"""
eletyp(model::Model) = eltype.(model.eleobj)

## Nodal results
"""
    dofres = getdof(state;[class=:X],field=:somefield,nodID=[nodids...],[orders=[0]])

Obtain the value of dofs of the same class and field, at various nodes and for various states.

If `state` is a vector, the output `dofres` has size `(ndof,nder+1,nstate)`.
If `state` is a scalar, the output `dofres` has size `(ndof,nder+1)`.

See also: [`getresult`](@ref), [`addnode!`](@ref), [`solve`](@ref)
"""
function getdof(state::State;kwargs...)  
    dofres = getdof([state];kwargs...)
    return reshape(dofres,size(dofres)[1:2]) 
end
function getdof(state::Vector{S};class::Symbol=:X,field::Symbol,nodID::Vector{NodID}=NodID[],order::ℤ=0)where {S<:State}
        class ∈ [:Λ,:X,:U,:A] || muscadeerror(sprintf("Unknown dof class %s",class))
    c     = class==:Λ      ? :X                                   : class
    dofID = nodID==NodID[] ? getdofID(state[begin].model,c,field) : getdofID(state[begin].model,c,field,nodID)
    dofres   = 𝕣2(undef,length(dofID),length(state)) 
    for istate ∈ eachindex(state)
        s = if class==:Λ; state[istate].Λ[order+1] 
        elseif class==:X; state[istate].X[order+1]    
        elseif class==:U; state[istate].U[order+1]    
        elseif class==:A; state[istate].A    
        end
        for (idof,d) ∈ enumerate(dofID)
            dofres[idof,istate] = s[d.idof] 
        end
    end
    return dofres
end
"""
    setdof!(state,value        ;[class=:X],field=:somefield,                  [order=0])
    setdof!(state,value::Vector;[class=:X],field=:somefield,nodID=[nodids...],[order=0])

Set the value of dofs of the same class and field, at various nodes and for various states.
There are two methods:
1. A single `value` is applied to all relevant nodes in the model
2. `value` and `nodID` are vectors of the same lengths, and each element in `value` is applied to the corresponding node.


See also: [`getresult`](@ref), [`addnode!`](@ref), [`solve`](@ref)
"""
function setdof!(state::State,dofval::𝕣1;class::Symbol=:X,field::Symbol,nodID::Vector{NodID},order::ℤ=0)
    class ∈ [:Λ,:X,:U,:A] || muscadeerror(sprintf("Unknown dof class %s",class))
    c     = class==:Λ ? :X : class
    dofID = getdofID(state.model,c,field,nodID)
    s = if class==:Λ; state.Λ[order+1] 
    elseif class==:X; state.X[order+1]    
    elseif class==:U; state.U[order+1]    
    elseif class==:A; state.A    
    end
    for (idof,d) ∈ enumerate(dofID)
        s[d.idof] = dofval[idof]  
    end
end
function setdof!(state::State,dofval::𝕣;class::Symbol=:X,field::Symbol,order::ℤ=0)
    class ∈ [:Λ,:X,:U,:A] || muscadeerror(sprintf("Unknown dof class %s",class))
    c     = class==:Λ ? :X : class
    dofID = getdofID(state.model,c,field)
    s = if class==:Λ; state.Λ[order+1] 
    elseif class==:X; state.X[order+1]    
    elseif class==:U; state.U[order+1]    
    elseif class==:A; state.A    
    end
    for d ∈ dofID
        s[d.idof] = dofval  
    end
end
# Elemental results

function extractkernel!(iele::AbstractVector{𝕫},eleobj::Vector{E},dis::EletypDisassembler,state::Vector{S},dbg,req) where{E,S<:State}# typestable kernel
    return [begin
        index = dis.index[i]
        Λ     = s.Λ[1][index.X]                 
        X     = Tuple(Xᵢ[index.X] for Xᵢ∈s.X)
        U     = Tuple(Uᵢ[index.U] for Uᵢ∈s.U)
        A     = s.A[index.A]
        L,FB,e = getlagrangian(eleobj[i],Λ,X,U,A,s.time,s.SP,(dbg...,istep=istep,iele=i),req)
        e
    end for i∈iele, (istep,s)∈enumerate(state)]
end
"""
    eleres = getresult(state,req,els)

Obtain an array of nested `NamedTuples` and `NTuples` of element results.
`req` is a request defined using `@request`.
`state` a vector of `State`s or a single `State`.
`els` can be either
- a vector of `EleID`s (obtained from `addelement!`) all corresponding
  to the same concrete element type
- a concrete element type (see [`eletyp`](@ref)).

If `state` is a vector, the output `dofres` has size `(nele,nstate)`.
If `state` is a scalar, the output `dofres` has size `(nele)`.

See also: [`getdof`](@ref), [`@request`](@ref), [`@espy`](@ref), [`addelement!`](@ref), [`solve`](@ref), [`eletyp`](@ref)
"""
function getresult(state::Vector{S},req,eleID::Vector{EleID})where {S<:State}
    # Some elements all of same type, multisteps
    # eleres[iele,istep].gp[3].σ
    ieletyp             = eleID[begin].ieletyp
    all(e.ieletyp== ieletyp for e∈eleID) || muscadeerror("All elements must be of the same element type")
    eleobj              = state[begin].model.eleobj[ieletyp]
    dis                 = state[begin].dis.dis[ieletyp]
    iele                = [e.iele for e∈eleID]
    return extractkernel!(iele,eleobj,dis,state,(func=:getresult,ieletyp=ieletyp),req)
end

function getresult(state::Vector{S},req,::Type{E}) where{S<:State,E<:AbstractElement}
    # All elements within the type, multisteps
    # eleres[iele,istep].gp[3].σ
    ieletyp = findfirst(E.==eletyp(state[begin].model))
    isnothing(ieletyp) && muscadeerror("This type of element is not in the model.")
    eleobj              = state[begin].model.eleobj[ieletyp]
    dis                 = state[begin].dis.dis[ieletyp]
    iele                = eachindex(eleobj)
    return extractkernel!(iele,eleobj,dis,state,(func=:getresult,eletyp=E),req)
end    
# single step
# eleres[iele].gp[3].σ
getresult(state::State,req,args...) = flat(getresult([state],req,args...)) 

"""
    ilast = findlastassigned(state)

Find the index `ilast` of the element before the first non assigment element in a vector `state`.

In multistep analyses, `solve` returns a vector `state` of length equal to the number of steps
requested by the user.  If the analysis is aborted, `solve` still returns any available results
at the begining of `state`, and the vector `state[1:ilast]` is fully assigned.

See also: [`solve`](@ref)
"""     
findlastassigned(v::Vector) = findlast([isassigned(v,i) for i=1:length(v)])


