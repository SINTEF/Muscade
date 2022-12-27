struct AllAdofs <: DofGroup 
    scale :: 𝕣1
end
function AllAdofs(model::Model,dis)
    scale  = Vector{𝕣}(undef,getndof(model,:A))
    for di ∈ dis
        for i ∈ di.index
            scale[i.A] = di.scale.A
        end
    end
    return AllAdofs(scale)
end
function decrement!(s::State,a::𝕣1,gr::AllAdofs) 
    s.A .-= a.*gr.scale
end
Base.getindex(s::State,gr::AllAdofs) = s.A./gr.scale # not used by solver
getndof(gr::AllAdofs) = length(gr.scale)

#------------------------------------

struct AllΛXUdofs <: DofGroup 
    Λscale :: 𝕣1
    Xscale :: 𝕣1
    Uscale :: 𝕣1
    nX     :: 𝕣
    nU     :: 𝕣
end
function AllΛXUdofs(model::Model,dis)
    nX     = getndof(model,:X)
    nU     = getndof(model,:U)
    Λscale = Vector{𝕣}(undef,nX)
    Xscale = Vector{𝕣}(undef,nX)
    Uscale = Vector{𝕣}(undef,nU)
    for di ∈ dis
        for i ∈ di.index
            Λscale[i.X] = di.scale.Λ
            Xscale[i.X] = di.scale.X
            Uscale[i.U] = di.scale.U
        end
    end
    return AllΛXUdofs(Λscale,Xscale,Uscale,nX,nU)
end
function decrement!(s::State,y::𝕣1,gr::AllΛXUdofs) 
    nX,nU = length(s.X[1]),length(s.U[1])
    s.Λ    .-= y[    1: nX   ].*gr.Λscale
    s.X[1] .-= y[ nX+1:2nX   ].*gr.Xscale
    s.U[1] .-= y[2nX+1:2nX+nU].*gr.Uscale
end
function Base.getindex(s::State,gr::AllΛXUdofs) # not used by solver
    nX,nU = length(s.X[1]),length(s.U[1])
    y = 𝕣1(undef,2nX+nU)
    y[    1: nX   ] = s.Λ    ./gr.Λscale
    y[ nX+1:2nX   ] = s.X[1] ./gr.Xscale
    y[2nX+1:2nX+nU] = s.U[1] ./gr.Uscale
    return y
end
getndof(gr::AllΛXUdofs) = length(2gr.nX+gr.nU)

#------------------------------------

#asm[ieletyp][iele].iLy...
struct OUTstaticΛXU_A  
    Ly    :: 𝕣1
    La    :: 𝕣1
    Lyy   :: SparseMatrixCSC{𝕣,𝕫} 
    Lya   :: SparseMatrixCSC{𝕣,𝕫} 
    Laa   :: SparseMatrixCSC{𝕣,𝕫} 
end   
struct ASMstaticΛXU_A{nY,nA,nYY,nYA,nAA}  
    iLy   :: SVector{nY,𝕫}
    iLa   :: SVector{nA,𝕫}
    iLyy  :: SMatrix{nY,nY,𝕫,nYY} 
    iLya  :: SMatrix{nY,nA,𝕫,nYA} 
    iLaa  :: SMatrix{nA,nA,𝕫,nAA} 
end   
function prepare(::Type{ASMstaticΛXU_A},model::Model,dis) 
    Adofgr             = AllAdofs(  model,dis)
    Ydofgr             = AllΛXUdofs(model,dis)

    return out,asm,Adofgr,Ydofgr
end
function zero!(out::OUTstaticΛXU_A)
    out.Ly        .= 0
    out.La        .= 0
    out.Lyy.nzval .= 0
    out.Lya.nzval .= 0
    out.Laa.nzval .= 0
end
function addin!(out,asm,scale,eleobj,Λ,X,U,A, t,ε,dbg) 
    Nx,Nu,Na        = length(X[1]),length(U[1]),length(A) # in the element
    # TODO a adiff functions for this?
    Nz              = 2Nx+Nu+Na                           # Z = [Y;A]=[Λ;X;U;A]       
    iλ,ix,iu,ia     = 1:Nx, Nx+1:2Nx, 2Nx+1:2Nx+Nu, 2Nx+Nu+1:2Nx+Nu+Na # index into element vectors ΔZ and Lz
    ΔZ              = variate{2,Nz}(δ{1,Nz,𝕣}())                 
    ΔΛ,ΔX,ΔU,ΔA     = view(ΔZ,iλ),view(ΔZ,ix),view(ΔZ,iu),view(ΔZ,ia) # TODO Static?
    L               = scaledlagrangian(scale,eleobj, Λ+ΔΛ, (∂0(X)+ΔX,),(∂0(U)+ΔU,),A+ΔA, t,ε,dbg)
    Lz,Lzz          = value_∂{1,Nz}(∂{2,Nz}(L)) 
    iy              = 1:2Nx+Nu  
    out.La[asm.iLa]         += Lz[ia]  
    out.Ly[asm.iLy]         += Lz[iy]  
    out.Laa.nzval[asm.iLaa] += Lzz[ia,ia]
    out.Lya.nzval[asm.iLya] += Lzz[iy,ia]
    out.Lyy.nzval[asm.iLyy] += Lzz[iy,iy]
end

#------------------------------------

function staticXUA(pstate,dbg;model::Model,time::AbstractVector{𝕣},
    initial::State=State(model,Disassembler(model)),
    maxiter::ℤ=50,maxΔy::ℝ=1e-5,maxLy::ℝ=∞,maxΔa::ℝ=1e-5,maxLa::ℝ=∞,verbose::𝕓=true)

    verbose && @printf "    staticXUA solver\n\n"
    dis                = initial.dis
    asm,out,Adofgr,Ydofgr = prepare(ASMstaticΛXU_A,model,dis)
    cΔy²,cLy²,cΔa²,cLa²= maxΔy^2,maxLy^2,maxΔa^2,maxLa^2
    state              = allocate(pstate,[settime(deepcopy(initial),t) for t∈time]) 
    nA                 = getndof(model,:A)
    La                 = Vector{𝕣 }(undef,nA   )
    Laa                = Matrix{𝕣 }(undef,nA,nA)
    Δy                 = Vector{𝕣1}(undef,length(time))
    y∂a                = Vector{𝕣2}(undef,length(time))
    Δy²,Ly²            = Vector{𝕣 }(undef,length(time)),Vector{𝕣}(undef,length(time))
    for iiter          = 1:maxiter
        verbose && @printf "    A-iteration %3d\n" iiter
        La            .= 0
        Laa           .= 0
        for step     ∈ eachindex(time)
            assemble!(out,asm,dis,model,state[step], 0.,(dbg...,solver=:StaticXUA,step=step))
            Δy[ step]  = try out.Lyy\out.Ly  catch; muscadeerror(@sprintf("Incremental solution failed at step=%i, iiter=%i",step,iiter)) end
            y∂a[step]  = try out.Lyy\out.Lya catch; muscadeerror(@sprintf("Incremental solution failed at step=%i, iiter=%i",step,iiter)) end
            La       .+= out.La  - out.Lya' * Δy[ step]
            Laa      .+= out.Laa - out.Lya' * y∂a[step]
            Δy²[step],Ly²[step] = sum(Δy[step].^2),sum(out.Ly.^2)
        end    
        Δa             = Laa\La 
        Δa²,La²        = sum(Δa.^2),sum(La.^2)
        for step       ∈ eachindex(time)
            ΔY         = Δy[step] - y∂a[step] * Δa
            decrement!(state[step],ΔY,Ydofgr)
            decrement!(state[step],Δa,Adofgr)
        end    
        if all(Δy².≤cΔy²) && all(Ly².≤cLy²) && Δa².≤cΔa² && La².≤cLa² 
            verbose && @printf "\n    StaticXUA converged in %3d A-iterations.\n" iiter
            verbose && @printf "    maxₜ(|ΔY|)=%7.1e  maxₜ(|∂L/∂Y|)=%7.1e  |ΔA|=%7.1e  |∂L/∂A|=%7.1e\n" √(maximum(Δy²)) √(maximum(Ly²)) √(Δa²) √(La²)
            break#out of the iiter loop
        end
        iiter==maxiter && muscadeerror(@sprintf("no convergence after %3d iterations. |Δy|=%7.1e |Ly|=%7.1e |Δa|=%7.1e |La|=%7.1e\n",iiter,√(maximum(Δy²)),√(maximum(Ly²)),√(Δa²),√(La²)))
    end
    return
end


