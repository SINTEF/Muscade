######## state and initstate
# at each step, contains the complete, unscaled state of the system
struct State{Nxder,Nuder,D}
    Λ     :: 𝕣1
    X     :: NTuple{Nxder,𝕣1}
    U     :: NTuple{Nuder,𝕣1}
    A     :: 𝕣1
    time  :: 𝕣
    ε     :: 𝕣
    model :: Model
    dis   :: D
end
# a constructor that provides an initial state
State(model::Model,dis;time=-∞) = State(zeros(getndof(model,:X)),(zeros(getndof(model,:X)),),(zeros(getndof(model,:U)),),zeros(getndof(model,:A)),time,0.,model,dis)
settime(s,t) = State(s.Λ,s.X,s.U,s.A,t,0.,s.model,s.dis)  


## find the last assigned array-element in a vector 
lastassigned(state) = state
function lastassigned(v::Vector)
    i = findlast([isassigned(v,i) for i=1:length(v)])
    return isnothing(i) ? nothing : lastassigned(v[i])
end

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
# dis.dis[ieletyp].index.[iele].X|U|A[ieledof]
# dis.dis[ieletyp].scale.Λ|X|U|A[ieledof]
# dis.scaleΛ|X|U|A[imoddof]
struct Disassembler{nX,nU,nA}
    dis     :: Vector{EletypDisassembler} 
    scaleΛ  :: 𝕣1
    scaleX  :: 𝕣1
    scaleU  :: 𝕣1
    scaleA  :: 𝕣1
end
function Disassembler(model::Model)
    neletyp                   = length(model.eleobj)  
    dis                       = Vector{EletypDisassembler}(undef,neletyp)
    NX,NU,NA                  = getndof(model,(:X,:U,:A))
    scaleΛ                    = Vector{𝕣}(undef,NX) # scale for state
    scaleX                    = Vector{𝕣}(undef,NX)
    scaleU                    = Vector{𝕣}(undef,NU)
    scaleA                    = Vector{𝕣}(undef,NA)
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
                sA[iadof] = scale
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
                idof          = dofID.idof
                if     class == :X
                    ixdof    += 1
                    iX[ixdof] = idof  
                elseif class == :U
                    iudof    += 1
                    iU[iudof] = idof
                elseif class == :A
                    iadof    += 1
                    iA[iadof] = idof
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
    return Disassembler{NX,NU,NA}(dis,scaleΛ,scaleX,scaleU,scaleA)
end

#### DofGroup

struct DofGroup{T1,T2,T3,T4,T5,T6,T7,T8} 
    nX     :: 𝕫 # of the _model_
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
end
function DofGroup(dis::Disassembler,iΛ,iX,iU,iA) 
    # constructor for dofgroup with permutation within classe.  The datastructure of DofGroup supports dofgroups with arbitrary permutations - write another constructor
    nX,nU,nA    = length(dis.scaleX),length(dis.scaleU),length(dis.scaleA) # number of dofs in _model_
    nλ,nx,nu,na = length(iΛ),length(iX),length(iU),length(iA)              # number of dofs of each class in group
    jΛ,jX,jU,jA = gradientpartition(nλ,nx,nu,na)                               # we stack classes on top of each other in group vectors
    Λs,Xs,Us,As = dis.scaleΛ[iΛ],dis.scaleX[iX],dis.scaleU[iU],dis.scaleA[iA]
    return DofGroup(nX,nU,nA, iΛ,iX,iU,iA,  jΛ,jX,jU,jA, Λs,Xs,Us,As)
end
function decrement!(s::State,der::𝕫,y::𝕣1,gr::DofGroup) 
    for i ∈ eachindex(gr.iΛ); s.Λ[       gr.iΛ[i]] -= y[gr.jΛ[i]] * gr.scaleΛ[i]; end
    for i ∈ eachindex(gr.iX); s.X[der+1][gr.iX[i]] -= y[gr.jX[i]] * gr.scaleX[i]; end
    for i ∈ eachindex(gr.iU); s.U[der+1][gr.iU[i]] -= y[gr.jU[i]] * gr.scaleU[i]; end
    for i ∈ eachindex(gr.iA); s.A[       gr.iA[i]] -= y[gr.jA[i]] * gr.scaleA[i]; end
end
getndof(gr::DofGroup) = length(gr.iΛ)+length(gr.iX)+length(gr.iU)+length(gr.iA)
allΛdofs(  model::Model,dis) = DofGroup(dis, 1:getndof(model,:X),𝕫[],𝕫[],𝕫[])
allXdofs(  model::Model,dis) = DofGroup(dis, 𝕫[],1:getndof(model,:X),𝕫[],𝕫[])
allUdofs(  model::Model,dis) = DofGroup(dis, 𝕫[],𝕫[],1:getndof(model,:U),𝕫[])
allAdofs(  model::Model,dis) = DofGroup(dis, 𝕫[],𝕫[],𝕫[],1:getndof(model,:A))
allΛXUdofs(model::Model,dis) = DofGroup(dis, 1:getndof(model,:X),1:getndof(model,:X),1:getndof(model,:U),𝕫[])


######## Prepare assemblers

# asm[iarray,ieletyp][idof/ientry,iele] has value zero for terms from element gradient/hessian that are not to be added in. Otherwise, the value they
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
    for (ieletyp,di) ∈ enumerate(dis.dis)
        nΛ,nX,nU,nA = gradientstructure(dofgr,di) # number of dofs of each class in the gradient returned by an element
        iΛ,iX,iU,iA = gradientpartition(nΛ,nX,nU,nA)  # indices into said gradient
        # asm[ieletyp][idof,iele] (its a view)
        asm[ieletyp] = zeros(𝕫,nΛ+nX+nU+nA,length(di.index))
        for (iele,index) ∈ enumerate(di.index)
            asm[ieletyp][iΛ,iele] = nonzeros(Λ[index.X])  
            asm[ieletyp][iX,iele] = nonzeros(X[index.X])
            asm[ieletyp][iU,iele] = nonzeros(U[index.U])
            asm[ieletyp][iA,iele] = nonzeros(A[index.A])
        end
    end
    return 𝕣1(undef,getndof(dofgr))
end
function asmfullmat!(asm,iasm,jasm,nidof,njdof) 
    for ieletyp ∈ eachindex(iasm)
        nieledof,nele = size(iasm[ieletyp])
        njeledof      = size(jasm[ieletyp],1)
        asm[ieletyp]  = zeros(𝕫,nieledof*njeledof,nele)
        for iele=1:nele, jeledof=1:njeledof, ieledof=1:nieledof
            i,j = iasm[ieletyp][ieledof,iele], jasm[ieletyp][jeledof,iele]
            if (i≠0)  &&  (j≠0)
                ientry = ieledof+nieledof*(jeledof-1)
                asm[ieletyp][ientry,iele] = i+nieledof(j-1)
            end
        end
    end
    return 𝕣2(undef,nidof,njdof)
end
function asmmat!(asm,iasm,jasm,nidof,njdof) 
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
    colptr = 𝕫1(undef,njdof+1) # Column icol is in colptr[icol]:(colptr[icol+1]-1)
    colptr[njdof+1] = nnz+1
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
    return SparseMatrixCSC(nidof,njdof,colptr,rowval,nzval)   
end



######## Generic assembler

function assemble!(out,asm,dis,model,state,ε,dbg)
    zero!(out)
    for ieletyp ∈ eachindex(model.eleobj)
        eleobj  = model.eleobj[ieletyp]
        assemblesequential!(out,view(asm,:,ieletyp),dis.dis[ieletyp], eleobj,state,ε,(dbg...,ieletyp=ieletyp))
    end
end
function assemblesequential!(out,asm,dis,eleobj,state::State{Nxder,Nuder},ε,dbg) where{Nxder,Nuder}
    scale     = dis.scale
    for iele  ∈ 1:lastindex(eleobj)
        index = dis.index[iele]
        Λe    = state.Λ[index.X]                 
        Xe    = NTuple{Nxder}(x[index.X] for x∈state.X)
        Ue    = NTuple{Nuder}(u[index.U] for u∈state.U)
        Ae    = state.A[index.A]
        addin!(out,asm,iele,scale,eleobj[iele],Λe,Xe,Ue,Ae, state.time,ε,(dbg...,iele=iele))
    end
end

#### addin

function addin!(out::DenseArray,asm,iele,a) 
    for (i,ai) ∈ enumerate(a)
        j = asm[i,iele]
        if j≠0
            out[j]+=ai
        end
    end
end   
function addin!(outA::AbstractSparseArray,asm,iele,a)
    for (i,ai) ∈ enumerate(a)
        j = asm[i,iele]
        if j≠0
            out.nzval[j]+=ai
        end
    end
end

###### scaled functions

function scaledlagrangian(scale,eleobj::E,Λs,Xs::NTuple{Nxder},Us::NTuple{Nuder},As, t,ε,dbg) where{E<:AbstractElement,Nxder,Nuder}
    Λ     =       Λs.*scale.Λ                 
    X     = NTuple{Nxder}(xs.*scale.X for xs∈Xs)  # TODO Tuple is slow, not typestable
    U     = NTuple{Nuder}(us.*scale.U for us∈Us)
    A     =       As.*scale.A
    L     = lagrangian(eleobj,Λ,X,U,A, t,ε,dbg)
    hasnan(L) && muscadeerror((dbg...,eletype=E),"NaN in a Lagrangian or its partial derivatives")
    return L
end    
function scaledresidual(scale,eleobj::E, Xs::NTuple{Nxder},Us::NTuple{Nuder},As, t,ε,dbg) where{E<:AbstractElement,Nxder,Nuder} 
    X     = NTuple{Nxder}(xs.*scale.X for xs∈Xs)  # TODO Tuple is slow, not typestable
    U     = NTuple{Nuder}(us.*scale.U for us∈Us)
    A     =       As.*scale.A
    R     = scale.Λ .* residual(eleobj, X,U,A, t,ε,dbg) 
    hasnan(R) && muscadeerror(dbg,"NaN in a residual or its partial derivatives")
    return R
end

