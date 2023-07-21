######## The disassembler

struct XUA{T,nX,nU,nA} 
    X::SVector{nX,T}
    U::SVector{nU,T}
    A::SVector{nA,T}
end
struct ΛXUA{T,nX,nU,nA} 
    Λ::SVector{nX,T}
    X::SVector{nX,T}
    U::SVector{nU,T}
    A::SVector{nA,T}
end
struct EletypDisassembler{nX,nU,nA}
    index :: Vector{XUA{𝕫,nX,nU,nA}}
    scale :: ΛXUA{𝕣,nX,nU,nA}
end
# dis.dis[ieletyp].index.[iele].X|U|A[ieledof]      - disassembling model state into element dofs
# dis.dis[ieletyp].scale.Λ|X|U|A[ieledof]           - scaling each element type 
# dis.scaleΛ|X|U|A[imoddof]                         - scaling the model state
# dis.field  X|U|A[imoddof]                         - field of dofs in model state
struct Disassembler
    dis::Vector{EletypDisassembler}
    scaleΛ  :: 𝕣1
    scaleX  :: 𝕣1
    scaleU  :: 𝕣1
    scaleA  :: 𝕣1
    fieldX  :: Vector{Symbol}
    fieldU  :: Vector{Symbol}
    fieldA  :: Vector{Symbol}
end
function Disassembler(model::Model)
    neletyp                   = length(model.eleobj)  
    dis                       = Vector{EletypDisassembler}(undef,neletyp)
    NX,NU,NA                  = getndof(model,(:X,:U,:A))
    scaleΛ                    = Vector{𝕣}(undef,NX) # scale for state
    scaleX                    = Vector{𝕣}(undef,NX)
    scaleU                    = Vector{𝕣}(undef,NU)
    scaleA                    = Vector{𝕣}(undef,NA)
    fieldX                    = Vector{Symbol}(undef,NX)
    fieldU                    = Vector{Symbol}(undef,NU)
    fieldA                    = Vector{Symbol}(undef,NA)
    for ieletyp               = 1:neletyp
        nele                  = length(model.eleobj[ieletyp])  
        E                     = eltype(model.eleobj[ieletyp])
        nX,nU,nA              = getndof(E,(:X,:U,:A))
        sΛ,sX,sU,sA           = 𝕣1(undef,nX),𝕣1(undef,nX),𝕣1(undef,nU),𝕣1(undef,nA) # scale for element
        ixdof,iudof,iadof     = 0,0,0
        for dofID             ∈ model.ele[ieletyp][begin].dofID
            doftyp            = getdoftyp(model,dofID)
            class,scale       = doftyp.class,doftyp.scale
            if     class == :X
                ixdof        += 1
                sX[ixdof]     = scale
                sΛ[ixdof]     = scale * model.scaleΛ
            elseif class == :U
                iudof        += 1
                sU[iudof]     = scale
            elseif class == :A
                iadof        += 1
                sA[iadof]     = scale
            end
        end
        scale                 = ΛXUA{𝕣,nX,nU,nA}(sΛ,sX,sU,sA) # scale for element type
        iX,iU,iA              = 𝕫1(undef,nX),𝕫1(undef,nU),𝕫1(undef,nA)  # tmp arrays fof index into state of eledofs
        index                 = Vector{XUA{𝕫,nX,nU,nA}}(undef,nele)     # such indexes, for all elements in type
        for iele              = 1:nele
            ixdof,iudof,iadof = 0,0,0
            for dofID         ∈ model.ele[ieletyp][iele].dofID
                doftyp        = getdoftyp(model,dofID)
                class         = doftyp.class
                field         = doftyp.field
                idof          = dofID.idof  # model idof
                if     class == :X
                    ixdof    += 1
                    iX[ixdof] = idof  
                    fieldX[idof]= field
                elseif class == :U
                    iudof    += 1
                    iU[iudof] = idof
                    fieldU[idof]= field
                elseif class == :A
                    iadof    += 1
                    iA[iadof] = idof
                    fieldA[idof]= field
                else
                    muscadeerror("element dof class must be :X,:U or :A")
                end
            end
            index[iele]       = XUA{𝕫,nX,nU,nA}(iX,iU,iA)
            scaleΛ[iX]        = scale.Λ  # "assemble" element scales into state scales
            scaleX[iX]        = scale.X
            scaleU[iU]        = scale.U
            scaleA[iA]        = scale.A
        end # for iele
        dis[ieletyp]          = EletypDisassembler{nX,nU,nA}(index,scale)
    end # for ieletyp
    return Disassembler(dis,scaleΛ,scaleX,scaleU,scaleA,fieldX,fieldU,fieldA)
end

######## state and initstate
# at each step, contains the complete, unscaled state of the system
mutable struct State{Nxder,Nuder,TSP}
    Λ     :: 𝕣1
    X     :: NTuple{Nxder,𝕣1}
    U     :: NTuple{Nuder,𝕣1}
    A     :: 𝕣1
    time  :: 𝕣
    SP    :: TSP # solver parameter
    model :: Model
    dis   :: Disassembler
end
# a constructor that provides an initial state
State(model::Model,dis;time=-∞) = State(zeros(getndof(model,:X)),(zeros(getndof(model,:X)),),(zeros(getndof(model,:U)),),zeros(getndof(model,:A)),time,nothing,model,dis)
function State{nXder,nUder}(s::State,SP::TSP) where{nXder,nUder,TSP}
    X = ntuple(i->copy(∂n(s.X,i-1)),nXder)
    U = ntuple(i->copy(∂n(s.U,i-1)),nUder)
    State{nXder,nUder,TSP}(copy(s.Λ),X,U,copy(s.A),s.time,SP,s.model,s.dis)
end 
State{nXder,nUder}(s::State) where{nXder,nUder} = State{nXder,nUder}(s,nothing)

#### DofGroup

struct DofGroup{T1,T2,T3,T4,T5,T6,T7,T8} 
    nX     :: 𝕫 # of the _model
    nU     :: 𝕫
    nA     :: 𝕫

    iΛ     :: T1   # state.Λ[iΛ] <-> y[jΛ]*Λscale
    iX     :: T2 
    iU     :: T3 
    iA     :: T4 

    jΛ     :: T5 
    jX     :: T6 
    jU     :: T7 
    jA     :: T8 

    scaleΛ :: 𝕣1
    scaleX :: 𝕣1
    scaleU :: 𝕣1
    scaleA :: 𝕣1

    fieldΛ :: Vector{Symbol}
    fieldX :: Vector{Symbol}
    fieldU :: Vector{Symbol}
    fieldA :: Vector{Symbol}

end
function DofGroup(dis::Disassembler,iΛ,iX,iU,iA) 
    # constructor for dofgroup with permutation within class.  The datastructure of DofGroup supports dofgroups with arbitrary permutations - write another constructor
    nX,nU,nA    = length(dis.scaleX),length(dis.scaleU),length(dis.scaleA) # number of dofs in _model_
    nλ,nx,nu,na = length(iΛ),length(iX),length(iU),length(iA)              # number of dofs of each class in group
    jΛ,jX,jU,jA = gradientpartition(nλ,nx,nu,na)                               # we stack classes on top of each other in group vectors
    Λs,Xs,Us,As = dis.scaleΛ[iΛ],dis.scaleX[iX],dis.scaleU[iU],dis.scaleA[iA]
    Λf,Xf,Uf,Af = dis.fieldX[iΛ],dis.fieldX[iX],dis.fieldU[iU],dis.fieldA[iA]
    return DofGroup(nX,nU,nA, iΛ,iX,iU,iA,  jΛ,jX,jU,jA, Λs,Xs,Us,As, Λf,Xf,Uf,Af)
end
function decrement!(s::State,der::𝕫,y::𝕣1,gr::DofGroup) 
    for i ∈ eachindex(gr.iΛ); s.Λ[       gr.iΛ[i]] -= y[gr.jΛ[i]] * gr.scaleΛ[i]; end
    for i ∈ eachindex(gr.iX); s.X[der+1][gr.iX[i]] -= y[gr.jX[i]] * gr.scaleX[i]; end
    for i ∈ eachindex(gr.iU); s.U[der+1][gr.iU[i]] -= y[gr.jU[i]] * gr.scaleU[i]; end
    for i ∈ eachindex(gr.iA); s.A[       gr.iA[i]] -= y[gr.jA[i]] * gr.scaleA[i]; end
end
function increment!(s::State,der::𝕫,y::𝕣1,gr::DofGroup) 
    for i ∈ eachindex(gr.iΛ); s.Λ[       gr.iΛ[i]] += y[gr.jΛ[i]] * gr.scaleΛ[i]; end
    for i ∈ eachindex(gr.iX); s.X[der+1][gr.iX[i]] += y[gr.jX[i]] * gr.scaleX[i]; end
    for i ∈ eachindex(gr.iU); s.U[der+1][gr.iU[i]] += y[gr.jU[i]] * gr.scaleU[i]; end
    for i ∈ eachindex(gr.iA); s.A[       gr.iA[i]] += y[gr.jA[i]] * gr.scaleA[i]; end
end
function getdof!(s::State,der::𝕫,y::𝕣1,gr::DofGroup) 
    for i ∈ eachindex(gr.iΛ); y[gr.jΛ[i]] = s.Λ[       gr.iΛ[i]] / gr.scaleΛ[i]; end
    for i ∈ eachindex(gr.iX); y[gr.jX[i]] = s.X[der+1][gr.iX[i]] / gr.scaleX[i]; end
    for i ∈ eachindex(gr.iU); y[gr.jU[i]] = s.U[der+1][gr.iU[i]] / gr.scaleU[i]; end
    for i ∈ eachindex(gr.iA); y[gr.jA[i]] = s.A[       gr.iA[i]] / gr.scaleA[i]; end
end
getndof(gr::DofGroup) = length(gr.iΛ)+length(gr.iX)+length(gr.iU)+length(gr.iA)
allΛdofs(  model::Model,dis) = DofGroup(dis, 1:getndof(model,:X),𝕫[],𝕫[],𝕫[])
allXdofs(  model::Model,dis) = DofGroup(dis, 𝕫[],1:getndof(model,:X),𝕫[],𝕫[])
allUdofs(  model::Model,dis) = DofGroup(dis, 𝕫[],𝕫[],1:getndof(model,:U),𝕫[])
allAdofs(  model::Model,dis) = DofGroup(dis, 𝕫[],𝕫[],𝕫[],1:getndof(model,:A))
allΛXUdofs(model::Model,dis) = DofGroup(dis, 1:getndof(model,:X),1:getndof(model,:X),1:getndof(model,:U),𝕫[])
allΛXUAdofs(model::Model,dis) = DofGroup(dis, 1:getndof(model,:X),1:getndof(model,:X),1:getndof(model,:U),1:getndof(model,:A))


######## Prepare assemblers

# asm[iarray,ieletyp][ieledof/ientry,iele] has value zero for terms from element gradient/hessian that are not to be added in. Otherwise, the value they
# have is where in the matrix/vector/nzval to put the values

function indexedstate(gr::DofGroup)
    # create a "state"  (Λ,X,U,A) of indices into the group - with zeros for modeldofs not in group
    Λ        = zeros(𝕫,gr.nX)
    X        = zeros(𝕫,gr.nX)
    U        = zeros(𝕫,gr.nU)
    A        = zeros(𝕫,gr.nA)
    Λ[gr.iΛ] = gr.jΛ
    X[gr.iX] = gr.jX
    U[gr.iU] = gr.jU
    A[gr.iA] = gr.jA
    return Λ,X,U,A
end
function gradientstructure(dofgr,dis::EletypDisassembler)
    # number of dofs of each class in the gradient returned by an element
    # because adiff is what it is, the gradient contains either all or no dofs in any given class
    nΛ       = length(dofgr.iΛ)==0 ? 0 : length(dis.scale.Λ) 
    nX       = length(dofgr.iX)==0 ? 0 : length(dis.scale.X) 
    nU       = length(dofgr.iU)==0 ? 0 : length(dis.scale.U) 
    nA       = length(dofgr.iA)==0 ? 0 : length(dis.scale.A) 
    return nΛ,nX,nU,nA
end
function gradientpartition(nΛ,nX,nU,nA)
    # indices into the class partitions of the gradient returned by an element
    iΛ          =           (1:nΛ)
    iX          = nΛ      .+(1:nX)
    iU          = nΛ+nX   .+(1:nU) 
    iA          = nΛ+nX+nU.+(1:nA)
    return iΛ,iX,iU,iA
end
nonzeros(v) = v[v.≠0]
function asmvec!(asm,dofgr,dis) 
    # asm[ieletyp] == undef, please fill 
    Λ,X,U,A  = indexedstate(dofgr)      # create a state of indices into the group - with zeros for modeldofs not in group
    for ieletyp ∈ eachindex(dis.dis)
        asmvec_kernel!(asm,ieletyp,dofgr,dis.dis[ieletyp],Λ,X,U,A)
    end
    return 𝕣1(undef,getndof(dofgr))
end
function asmvec_kernel!(asm,ieletyp,dofgr,dis,Λ,X,U,A) 
    nΛ,nX,nU,nA = gradientstructure(dofgr,dis) # number of dofs of each class in the gradient returned by an element
    iΛ,iX,iU,iA = gradientpartition(nΛ,nX,nU,nA)  # indices into said gradient TODO type unstable, barrier function
    asm[ieletyp] = zeros(𝕫,nΛ+nX+nU+nA,length(dis.index)) # asm[ieletyp][idof,iele] (its a view)
    for (iele,index) ∈ enumerate(dis.index)
        asm[ieletyp][iΛ,iele] .= nonzeros(Λ[index.X])  
        asm[ieletyp][iX,iele] .= nonzeros(X[index.X])
        asm[ieletyp][iU,iele] .= nonzeros(U[index.U])
        asm[ieletyp][iA,iele] .= nonzeros(A[index.A])
    end
end
function asmfullmat!(asm,iasm,jasm,nimoddof,njmoddof) 
    for ieletyp ∈ eachindex(iasm)
        nieledof,nele = size(iasm[ieletyp])
        njeledof      = size(jasm[ieletyp],1)
        asm[ieletyp]  = zeros(𝕫,nieledof*njeledof,nele)
        for iele=1:nele, jeledof=1:njeledof, ieledof=1:nieledof
            imoddof,jmoddof = iasm[ieletyp][ieledof,iele], jasm[ieletyp][jeledof,iele]
            if (imoddof≠0)  &&  (jmoddof≠0)
                ientry = ieledof+nieledof*(jeledof-1)
                asm[ieletyp][ientry,iele] = imoddof+nimoddof*(jmoddof-1)
            end
        end
    end
    return 𝕣2(undef,nimoddof,njmoddof)
end
function asmmat!(asm,iasm,jasm,nimoddof,njmoddof) 
    # 1) traverse all eletyp
    #    compute number npairs of contribution
    npair = 0
    for ieletyp ∈ eachindex(iasm)
        for iele = 1:size(iasm[ieletyp],2)
            npair += sum(iasm[ieletyp][:,iele].≠0)*sum(jasm[ieletyp][:,iele].≠0)
        end
    end
    # 2) traverse all elements 
    #       prepare a Vector A of all (jmoddof,imoddof) (in that order, for sort to work!) pairs of model dofs ::Vector{Tuple{Int64, Int64}}(undef,N)
    A = Vector{Tuple{𝕫,𝕫}}(undef,npair)
    ipair = 0
    for ieletyp ∈ eachindex(iasm)
        nieledof,nele = size(iasm[ieletyp])
        njeledof      = size(jasm[ieletyp],1)
        for iele=1:nele, jeledof=1:njeledof, ieledof=1:nieledof
            if (iasm[ieletyp][ieledof,iele]≠0)  &&  (jasm[ieletyp][jeledof,iele]≠0)
                ipair += 1
                A[ipair] = (jasm[ieletyp][jeledof,iele] , iasm[ieletyp][ieledof,iele]) # NB: (j,i), not (i,j), because of lexicographic sortperm
            end
        end
    end
    # 3) sortperm(A)
    I = sortperm(A)
    # 4) traverse A[I] 
    #      count nnz
    #      create a list J that to each element of A[I] associates an entry 1≤inz≤nnz into nzval
    #      prepare sparse
    nnz    = 0
    for ipair = 1:npair
        if (ipair==1) || (A[I[ipair]]≠A[I[ipair-1]]) 
            nnz +=1
        end
    end    
    J      = 𝕫1(undef,npair) # to each pair in A[I] associate a unique entry number
    K      = 𝕫1(undef,npair) # to each pair in A    associate a unique entry number
    nzval  = ones(𝕣,nnz) # could this be left undef and still get past the sparse constructor?
    colptr = 𝕫1(undef,njmoddof+1) # Column icol is in colptr[icol]:(colptr[icol+1]-1)
    colptr[njmoddof+1] = nnz+1
    rowval = 𝕫1(undef,nnz)
    inz    = 0
    icol   = 1
    colptr[icol] = inz+1
    for ipair = 1:npair
        if (ipair==1) || (A[I[ipair]]≠A[I[ipair-1]]) 
            inz +=1
            (j,i) = A[I[ipair]] # NB: (j,i), not (i,j)
            rowval[inz] = i
            while j>icol
                icol +=1
                colptr[icol] = inz  
            end
        end
        J[ipair] = inz 
    end    
    K[I] = J
    # 5) traverse all elements again to distribute J into asm
    ipair = 0
    for ieletyp ∈ eachindex(iasm)
        nieledof,nele = size(iasm[ieletyp]  )
        njeledof      = size(jasm[ieletyp],1)
        asm[ieletyp]  = zeros(𝕫,nieledof*njeledof,nele)
        for iele=1:nele, jeledof=1:njeledof, ieledof=1:nieledof
            if (iasm[ieletyp][ieledof,iele]≠0)  &&  (jasm[ieletyp][jeledof,iele]≠0)
                ipair += 1
                ientry = ieledof+nieledof*(jeledof-1) 
                asm[ieletyp][ientry,iele] = K[ipair]  
            end
        end
    end
    # 6)
    return SparseMatrixCSC(nimoddof,njmoddof,colptr,rowval,nzval)   
end


######## Generic assembler
abstract type Assembly end
using Base.Threads

# sequential

function assemble!(out::Assembly,asm,dis,model,state,dbg) 
    zero!(out)
    for ieletyp = 1:lastindex(model.eleobj)
        eleobj  = model.eleobj[ieletyp]
        assemble_!(out,view(asm,:,ieletyp),dis.dis[ieletyp],eleobj,state,state.SP,(dbg...,ieletyp=ieletyp))
    end
end
function assemble_!(out::Assembly,asm,dis,eleobj,state::State{Nxder,Nuder},SP,dbg) where{Nxder,Nuder}
    scale     = dis.scale
    for iele  = 1:lastindex(eleobj)
        index = dis.index[iele]
        Λe    = state.Λ[index.X]                 
        Xe    = NTuple{Nxder}(x[index.X] for x∈state.X)
        Ue    = NTuple{Nuder}(u[index.U] for u∈state.U)
        Ae    = state.A[index.A]
        addin!(out,asm,iele,scale,eleobj[iele],Λe,Xe,Ue,Ae, state.time,SP,(dbg...,iele=iele))
    end
end

# multithreaded
one_for_each_thread(x) = SVector{nthreads()}(deepcopy(x) for i=1:nthreads())
firstelement(x::AbstractVector) = x[1]
firstelement(x                ) = x

function add!(a::Array,b::Array)
    for i∈eachindex(a)
        a[i] += b[i]
    end
end
function add!(a::SparseMatrixCSC,b::SparseMatrixCSC) # assumes identical sparsity structure
    for i∈eachindex(a.nzval)
        a.nzval[i] += b.nzval[i]
    end
end

function assemble!(out::AbstractVector{A},asm,dis,model,state,dbg) where{A<:Assembly}
    for i = 1:nthreads() 
        zero!(out[i])
    end
    for ieletyp = 1:lastindex(model.eleobj)
        eleobj  = model.eleobj[ieletyp]
        assemble_!(out,view(asm,:,ieletyp),dis.dis[ieletyp], eleobj,state,state.SP,(dbg...,ieletyp=ieletyp))
    end
    for i = 2:nthreads() 
        add!(out[1],out[i])
    end
end

function assemble_!(out::AbstractVector{A},asm,dis,eleobj,state::State{Nxder,Nuder},SP,dbg) where{Nxder,Nuder,A<:Assembly}
    scale     = dis.scale
    @threads for iele  = 1:lastindex(eleobj)
        index = dis.index[iele]
        Λe    = state.Λ[index.X]                 
        Xe    = NTuple{Nxder}(x[index.X] for x∈state.X)
        Ue    = NTuple{Nuder}(u[index.U] for u∈state.U)
        Ae    = state.A[index.A]
        addin!(out[threadid()],asm,iele,scale,eleobj[iele],Λe,Xe,Ue,Ae, state.time,SP,(dbg...,iele=iele))
    end
end


#######

# assemble! calls MySolver/addin!, which calls getresidual or getlagrangian

####### Lagrangian from residual and residual from Lagrangian
const True,False  = Val{true},Val{false}
@generated function implemented(eleobj) 
#                                    δX,X,     U,     A, t,χ,  χcv,     SP,       dbg    
    r = hasmethod(residual  ,(eleobj,   NTuple,NTuple,𝕣1,𝕣,Any,Function,NamedTuple,NamedTuple))
    l = hasmethod(lagrangian,(eleobj,𝕣1,NTuple,NTuple,𝕣1,𝕣,Any,Function,NamedTuple,NamedTuple))
    return :(Val{$r},Val{$l})
end

function checkresidual(eleobj::AbstractElement,X,U,A,t,χ,χcv,SP,dbg,req...)
    res = residual(eleobj,X,U,A,t,χ,χcv,SP,dbg,req...)
    hasnan(res[1]) && muscadeerror((dbg...,t=t,SP=SP),
                                "NaN in a residual or its partial derivatives")
    return res
end
function checklagrangian(eleobj::AbstractElement,Λ,X,U,A,t,χ,χcv,SP,dbg,req...)
    res = lagrangian(eleobj,Λ,X,U,A,t,χ,χcv,SP,dbg,req...)
    hasnan(res[1]) && muscadeerror((dbg...,t=t,SP=SP),
                                "NaN in a lagrangian or its partial derivatives")
    return res
end

#               has residual  has lagrangian
getresidual(  ::Type{False},::Type{False},eleobj::AbstractElement,  X,U,A,t,χ,χcv,SP,dbg,req...) = muscadeerror(dbg,@sprintf("Element %s must have method 'Muscade.lagrangian' or/and 'Muscade.residual' with correct interface",typeof(eleobj)))
getlagrangian(::Type{False},::Type{False},eleobj::AbstractElement,Λ,X,U,A,t,χ,χcv,SP,dbg,req...) = muscadeerror(dbg,@sprintf("Element %s must have method 'Muscade.lagrangian' or/and 'Muscade.residual' with correct interface",typeof(eleobj)))
getresidual(  ::Type{True },::Type{<:Val},eleobj::AbstractElement,  X,U,A,t,χ,χcv,SP,dbg,req...) = checkresidual(  eleobj,  X,U,A,t,χ,χcv,SP,dbg,req...)
getlagrangian(::Type{<:Val},::Type{True },eleobj::AbstractElement,Λ,X,U,A,t,χ,χcv,SP,dbg,req...) = checklagrangian(eleobj,Λ,X,U,A,t,χ,χcv,SP,dbg,req...)    

# want residual, lagrangian implemented
function getresidual(::Type{False},::Type{True} ,eleobj::AbstractElement,X,U,A,t,χ,χcv,SP,dbg,req...)  
    P   = constants(∂0(X),∂0(U),A,t)
    Nx  = length(∂0(X)) # TODO this does no generalize to dynamics
    Λ   = δ{P,Nx,𝕣}() 
    L,χn,FB,eleres... = checklagrangian(eleobj,Λ,X,U,A,t,χ,χcv,SP,dbg,req...)    
    return ∂{P,Nx}(L),χn,FB,eleres...
end
# want lagrangian, residual implemented
function getlagrangian(::Type{True} ,::Type{False},eleobj::AbstractElement,Λ,X,U,A,t,χ,χcv,SP,dbg,req...) 
    R,χn,FB,eleres... = checkresidual(  eleobj,  X,U,A,t,χ,χcv,SP,dbg,req...)
    return Λ ∘₁ R ,χn,FB,eleres...
end


#### zero!
function zero!(out::DenseArray)
    for i∈eachindex(out)
        out[i] = 0
    end
end
function zero!(out::AbstractSparseArray)
    for i∈eachindex(out.nzval)
        out.nzval[i] = 0
    end
end

#### extract value or derivatives from a SVector 'a' of adiffs, and add it directly into vector, full matrix or sparse matrix 'out'.
function add_value!(out::𝕣1,asm,iele,a::SVector{M,∂ℝ{P,N,𝕣}},ias) where{P,N,M}
    for (iasm,ia) ∈ enumerate(ias)
        iout = asm[iasm,iele]
        if iout≠0
            out[iout]+=a[ia].x
        end
    end
end   
function add_value!(out::𝕣1,asm,iele,a::SVector{M,𝕣},ias) where{M}
    for (iasm,ia) ∈ enumerate(ias)
        iout = asm[iasm,iele]
        if iout≠0
            out[iout]+=a[ia]
        end
    end
end   
add_value!(out,asm,iele,a) = add_value!(out,asm,iele,a,eachindex(a)) 
struct add_∂!{P} end 
function add_∂!{P}(out::Array,asm,iele,a::SVector{M,∂ℝ{P,N,R}},i1as,i2as) where{P,N,R,M}
    for (i1asm,i1a) ∈ enumerate(i1as), (i2asm,i2a) ∈ enumerate(i2as)
        iasm = i1asm+length(i1as)*(i2asm-1)
        iout = asm[iasm,iele]
        if iout≠0
            out[iout]+=a[i1a].dx[i2a]  
        end
    end
end  
add_∂!{P}(out::SparseMatrixCSC,args...) where{P}                      = add_∂!{P}(out.nzval,args...)
add_∂!{P}(out::Array,asm,iele,a::SVector{M,R},args...) where{P,M,R}   = nothing
add_∂!{P}(out::Array,asm,iele,a::SVector{M,∂ℝ{P,N,R}}) where{P,N,R,M} = add_∂!{P}(out,asm,iele,a,SVector{M}(1:M),SVector{N}(1:N))


