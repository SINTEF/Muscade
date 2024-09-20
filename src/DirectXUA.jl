# dis.dis[ieletyp].index[iele].X|U|A[ieledof]       - disassembling model state into element dofs
# dis.dis[ieletyp].scale.Λ|X|U|A[ieledof]           - scaling each element type 
# dis.scaleΛ|X|U|A[imoddof]                         - scaling the model state
# dis.field  X|U|A[imoddof]                         - field of dofs in model state
# asm1[iarray,ieletyp][ieledof|ientry,iele] -> idof|inz
# out1.L1[α  ][αder     ][idof] -> gradient     α∈λxua
# out1.L2[α,β][αder,βder][inz ] -> Hessian      α∈λxua, β∈λxua
const λxua   = 1:4
const λxu    = 1:3
const xu     = 2:3
const ind    = (Λ=1,X=2,U=3,A=4)
const nclass = length(ind) 

## Assembly of sparse
arrnum(α  )  =          α
arrnum(α,β)  = nclass + β + nclass*(α-1) 
mutable struct AssemblyDirect{NDX,NDU,NA,T1,T2}  <:Assembly
    L1 :: T1   
    L2 :: T2   
end  
function prepare(::Type{AssemblyDirect},model,dis,NDX,NDU,NA;Uwhite=false,Xwhite=false,XUindep=false,UAindep=false,XAindep=false) 
    dofgr    = (allΛdofs(model,dis),allXdofs(model,dis),allUdofs(model,dis),allAdofs(model,dis))
    ndof     = getndof.(dofgr)
    neletyp  = getneletyp(model)
    asm      = Matrix{𝕫2}(undef,nclass+nclass^2,neletyp)
    nder     = (1,NDX,NDU,NA)
    L1 = Vector{Vector{Vector{𝕣}}}(undef,4)
    for α∈λxua
        nα = nder[α]
        if Uwhite  && α==ind.U          nα=1 end   # U-prior is white noise process
        av = asmvec!(view(asm,arrnum(α),:),dofgr[α],dis)
        L1[α] = Vector{Vector{𝕣}}(undef,nα)
        for αder=1:nα 
            L1[α][αder] = copy(av)
        end
    end
    L2 = Matrix{Matrix{SparseMatrixCSC{Float64, Int64}}}(undef,4,4)
    for α∈λxua, β∈λxua
        am = asmmat!(view(asm,arrnum(α,β),:),view(asm,arrnum(α),:),view(asm,arrnum(β),:),ndof[α],ndof[β])
        nα,nβ = nder[α], nder[β]
        if            α==β==ind.Λ          nα,nβ=0,0 end   # Lλλ is always zero
        if Uwhite  && α==β==ind.U          nα,nβ=1,1 end   # U-prior is white noise process
        if Xwhite  && α==β==ind.X          nα,nβ=1,1 end   # X-measurement error is white noise process
        if XUindep && α==ind.X && β==ind.U nα,nβ=0,0 end   # X-measurements indep of U
        if XUindep && α==ind.U && β==ind.X nα,nβ=0,0 end   # X-measurements indep of U
        if XAindep && α==ind.X && β==ind.A nα,nβ=0,0 end   # X-measurements indep of A
        if XAindep && α==ind.A && β==ind.X nα,nβ=0,0 end   # X-measurements indep of A
        if UAindep && α==ind.U && β==ind.A nα,nβ=0,0 end   # U-load indep of A
        if UAindep && α==ind.A && β==ind.U nα,nβ=0,0 end   # U-load  indep of A
        L2[α,β] = Matrix{SparseMatrixCSC{Float64, Int64}}(undef,nα,nβ)
        for αder=1:nα,βder=1:nβ
            L2[α,β][αder,βder] = copy(am)
        end
    end
    out      = AssemblyDirect{NDX,NDU,NA,typeof(L1),typeof(L2)}(L1,L2)
    return out,asm
end
function zero!(out::AssemblyDirect)
    for α∈λxua 
        zero!.(out.L1[α])
        for β∈λxua
            zero!.(out.L2[α,β])
        end
    end
end

function addin!(out::AssemblyDirect{NDX,NDU,NA,T1,T2},asm,iele,scale,eleobj,Λ::NTuple{1  ,SVector{Nx}},
                                                                            X::NTuple{NDX,SVector{Nx}},
                                                                            U::NTuple{NDU,SVector{Nu}},
                                                                            A::           SVector{Na} ,t,SP,dbg) where{NDX,NDU,NA,T1,T2,Nx,Nu,Na} 
    ndof  = (Nx, Nx, Nu, Na)
    Nz    = Nx + Nx*NDX + Nu*NDU + Na*NA
    nder  = (1,NDX,NDU,NA)

    Λ∂ =              SVector{Nx}(∂²ℝ{1,Nz}(Λ[1   ][idof],                           idof)   for idof=1:Nx)
    X∂ = ntuple(ider->SVector{Nx}(∂²ℝ{1,Nz}(X[ider][idof],Nx+Nx*(ider-1)            +idof)   for idof=1:Nx),NDX)
    U∂ = ntuple(ider->SVector{Nu}(∂²ℝ{1,Nz}(U[ider][idof],Nx+Nx*NDX     +Nu*(ider-1)+idof)   for idof=1:Nu),NDU)
    if NA == 1
        A∂   =        SVector{Na}(∂²ℝ{1,Nz}(A[      idof],Nx+Nx*NDX     +Nu*NDU     +idof)   for idof=1:Na)
        L,FB = getlagrangian(eleobj, Λ∂,X∂,U∂,A∂,t,SP,dbg)
    else
        L,FB = getlagrangian(eleobj, Λ∂,X∂,U∂,A ,t,SP,dbg)
    end
 
    ∇L           = ∂{2,Nz}(L)
    pα           = 0   # points into the partials, 1 entry before the start of relevant partial derivative in α,ider-loop
    for α∈λxua, i=1:nder[α]   # we must loop over all time derivatives to correctly point into the adiff-partials...
        iα       = pα.+(1:ndof[α])
        pα      += ndof[α]
        Lα = out.L1[α]
        if i≤size(Lα,1)  # ...but only add into existing vectors of L1, for speed
            add_value!(out.L1[α][i] ,asm[arrnum(α)],iele,∇L,iα)
        end
        pβ       = 0
        for β∈λxua, j=1:nder[β]
            iβ   = pβ.+(1:ndof[β])
            pβ  += ndof[β]
            Lαβ = out.L2[α,β]
            if i≤size(Lαβ,1) && j≤size(Lαβ,2) # ...but only add into existing matrices of L2, for better sparsity
                add_∂!{1}(out.L2[α,β][i,j],asm[arrnum(α,β)],iele,∇L,iα,iβ)
            end
        end
    end
end

## Assembly of bigsparse
function makepattern(NDX,NDU,NA,nstep,out)
    # Looking at all steps, class, order of fdiff and Δstep, for rows and columns: which blocks are actualy nz?
    nder = (1,NDX,NDU)
    αblk = 𝕫1(undef,0)
    βblk = 𝕫1(undef,0)
    nz   = Vector{SparseMatrixCSC{𝕣,𝕫}}(undef,0)
    for step = 1:nstep
        for     α∈λxu 
            for β∈λxu
                Lαβ = out.L2[α,β]
                for     αder = 1:size(Lαβ,1)
                    for βder = 1:size(Lαβ,2)
                        for     iα ∈ finitediff(αder-1,nstep,step;transposed=true)
                            for iβ ∈ finitediff(βder-1,nstep,step;transposed=true)
                                push!(αblk,3*(step+iα.Δs-1)+α)
                                push!(βblk,3*(step+iβ.Δs-1)+β)
                                push!(nz  ,Lαβ[1,1]  )
                            end
                        end
                    end 
                end
            end
        end
    end   
    u    = unique(i->(αblk[i],βblk[i]),eachindex(αblk))
    αblk = αblk[u]
    βblk = βblk[u]
    nz   = nz[  u]

    if NA==1
        Ablk = 3*nstep+1
        push!(αblk,Ablk                      )  
        push!(βblk,Ablk                      )
        push!(nz  ,out.L2[ind.A,ind.A][1,1]  )
        for step = 1:nstep
            for     α∈λxu 
                # loop over derivatives and finitediff is optimized out, as time derivatives will only 
                # be added into superbloc already reached by non-derivatives. No, it's not a bug...
                if size(out.L2[ind.A,α],1)>0
                    push!(αblk,Ablk                  )
                    push!(βblk,3*(step-1)+α          )  
                    push!(nz  ,out.L2[ind.A,α][1,1]  )
                    push!(αblk,3*(step-1)+α          )  
                    push!(βblk,Ablk                  )
                    push!(nz  ,out.L2[α,ind.A][1,1]  )
                end
            end
        end
    end
   return sparse(αblk,βblk,nz)
end

function preparebig(NDX,NDU,NA,nstep,out)
    # create an assembler and allocate for the big linear system
    pattern                  = makepattern(NDX,NDU,NA,nstep,out)
    Lvv,bigasm               = prepare(pattern)
    Lv                       = 𝕣1(undef,size(Lvv,1))
    return Lv,Lvv,bigasm
end
###

function assemblebig!(Lvv,Lv,bigasm,asm,model,dis,out::AssemblyDirect{NDX,NDU,NA},state,nstep,Δt,γ,dbg) where{NDX,NDU,NA}
    zero!(Lvv)
    zero!(Lv )
    for step = 1:nstep
        state[step].SP   = (γ=γ ,)
        
        assemble!(out,asm,dis,model,state[step],(dbg...,asm=:assemblebig!,step=step))

        for β∈λxu
            Lβ = out.L1[β]
            for βder = 1:size(Lβ,1)
                s = Δt^-βder
                for iβ ∈ finitediff(βder-1,nstep,step;transposed=true)
                    βblk = 3*(step+iβ.Δs-1)+β
                    addin!(bigasm,Lv ,Lβ[βder],βblk,iβ.w*s) 
                end
            end
        end
        for     α∈λxu 
            for β∈λxu
                Lαβ = out.L2[α,β]
                for     αder = 1:size(Lαβ,1)
                    for βder = 1:size(Lαβ,2)
                        s = Δt^-(αder+βder)
                        for     iα ∈ finitediff(αder-1,nstep,step;transposed=true)
                            for iβ ∈ finitediff(βder-1,nstep,step;transposed=true)
                                αblk = 3*(step+iα.Δs-1)+α
                                βblk = 3*(step+iβ.Δs-1)+β
                                addin!(bigasm,Lvv,Lαβ[αder,βder],αblk,βblk,iα.w*iβ.w*s) 
                            end
                        end
                    end 
                end
            end
        end
        if NA==1
            Ablk = 3*nstep+1   
            addin!(bigasm,Lv ,out.L1[ind.A      ][1  ],Ablk     )
            addin!(bigasm,Lvv,out.L2[ind.A,ind.A][1,1],Ablk,Ablk)
            for α∈λxu
                Lαa = out.L2[α    ,ind.A]
                Laα = out.L2[ind.A,α    ]
                for αder = 1:size(Lαa,1)  # size(Lαa,1)==size(Laα,2) because these are 2nd derivatives of L
                    s = Δt^-αder
                    for iα ∈finitediff(αder-1,nstep,step;transposed=true)
                        αblk = 3*(step+iα.Δs-1)+α
                        addin!(bigasm,Lvv,Lαa[αder,1   ],αblk,Ablk,iα.w*s) 
                        addin!(bigasm,Lvv,Laα[1   ,αder],Ablk,αblk,iα.w*s) 
                    end
                end
            end
        end
    end   
end


"""
	DirectXUA

A non-linear direct solver for optimisation FEM.

An analysis is carried out by a call with the following syntax:

```
initialstate    = initialize!(model)
setdof!(initialstate,1.;class=:U,field=:λcsr)
stateX          = solve(SweepX{0}  ;initialstate=initialstate,time=[0.,1.])
stateXUA        = solve(DirectXUA;initialstate=stateX)
```

The interior point algorithm requires a starting point that is
strictly primal feasible (at all steps, all inequality constraints must have 
positive gaps) and strictly dual feasible (at all steps, all associated Lagrange 
multipliers must be strictly positive). Note the use of `setdof!` in the example
above to ensure dual feasibility.

# Named arguments
- `dbg=(;)`           a named tuple to trace the call tree (for debugging)
- `verbose=true`      set to false to suppress printed output (for testing)
- `silenterror=false` set to true to suppress print out of error (for testing) 
- `initialstate`      a vector of `state`s, one for each load case in the optimization problem, 
                      obtained from one or several previous `SweepX` analyses
- `maxiter=50`        maximum number of Newton-Raphson iterations 
- `maxΔa=1e-5`        "outer" convergence criteria: a norm on the scaled `A` increment 
- `maxΔy=1e-5`        "inner" convergence criteria: a norm on the scaled `Y=[ΛXU]` increment 
- `saveiter=false`    set to true so that the output `state` is a vector (over the Aiter) of 
                      vectors (over the steps) of `State`s of the model (for debugging 
                      non-convergence). 
- `maxLineIter=50`    maximum number of iterations in the linear search that ensure interior points   
- `β=0.5`             `β∈]0,1[`. In the line search, if conditions are not met, then a new line-iteration is done
                      with `s *= β` where  `β→0` is a hasty backtracking, while `β→1` stands its ground.            
- `γfac=0.5`          `γfac∈[0,1[`. At each iteration, the barrier parameter γ is taken as `γ = (∑ⁿᵢ₌₁ λᵢ gᵢ)/n*γfac` where
                      `(∑ⁿᵢ₌₁ λᵢ gᵢ)/n` is the complementary slackness, and `n` the number of inequality constraints.
- `γbot=1e-8`         `γ` will not be reduced to under the original complementary slackness divided by `γbot`,
                      to avoid conditioning problems.                                               

# Output

A vector of length equal to that of `initialstate` containing the state of the optimized model at each of these steps.                       

See also: [`solve`](@ref), [`SweepX`](@ref), [`setdof!`](@ref) 
"""
struct DirectXUA{NDX,NDU,NA} <: AbstractSolver end 
# function solve(::Type{DirectXUA{NDX,NDU,NA}},pstate,verbose::𝕓,dbg;
#     time::AbstractRange{𝕣},
#     initialstate::State,
#     maxiter::ℤ=50,
#     maxΔλ::ℝ=1e-5,maxΔx::ℝ=1e-5,maxΔu::ℝ=1e-5,maxΔa::ℝ=1e-5,
#     saveiter::𝔹=false
#      kwargs...) where{NDX,NDU,NA}

#     nstep                 = length(time)
#     Δt                    = (last(time)-first(time))/(nstep-1)

#     model,dis             = initialstate.model, initialstate.dis
#     out1,asm1             = prepare(AssemblyDirect    ,model,dis,NDX,NDU,NA;kwargs...)
#     assemble!(out1,asm1,dis,model,initialstate,(dbg...,solver=:DirectXUA,phase=:sparsity))
#     Lv,Lvv,bigasm         = preparebig(NDX,NDU,NA,nstep,out1)

#     state                 = [State{1,NDX,NDU,@NamedTuple{γ::Float64}}(copy(initialstate)) for timeᵢ ∈ time]    
#     for (step,timeᵢ) ∈ enumerate(time)
#         state[step].time = timeᵢ
#     end
#     pstate[]              = state                                                                            # TODO pstate typestable???
#     if saveiter
#         stateiter         = Vector{typeof(state)}(undef,maxiter) 
#         pstate[]          = stateiter
#     end    

#     Δλ²                   = Vector{𝕣}(undef,nstep)
#     Δx²                   = Vector{𝕣}(undef,nstep)
#     Δu²                   = Vector{𝕣}(undef,nstep)
#     maxΔλ²                = maxΔλ 
#     maxΔx²                = maxΔx 
#     maxΔu²                = maxΔu 
#     maxΔa²                = maxΔa 

#     local LU
#     for iter              = 1                                                                                 # TODO 1:maxiter
#         verbose && @printf("    iteration %3d, γ=%g\n",iter,γ)

#         assemblebig!(Lvv,Lv,bigasm,asm1,model,dis,out1,state,nstep,Δt,γ,(dbg...,solver=:DirectXUA,iter=iter))

#         try if iter==1 LU = lu(Lvv) 
#         else           lu!(LU ,Lvv)
#         end catch; muscadeerror(@sprintf("Lvv matrix factorization failed at iter=%i",iter));end
#         Δv               = LU\Lv 


        
#         Δa               = getblock(Δv,bigasm,3*nstep+1)
#         Δa²              = sum(Δa.^2)
#         for stateᵢ   ∈ state
#             decrement!(stateᵢ,0,Δa,Adofgr)
#         end    
#         for order = 0:ND-1 # TODO
#             for (step,stateᵢ)   ∈ enumerate(state)
#                 Δλ           = getblock(Δv,bigasm,3*step-2)
#                 Δx           = getblock(Δv,bigasm,3*step-1)
#                 Δu           = getblock(Δv,bigasm,3*step-0)
#                 Δy²[step]    = sum(Δλ.^2)
#                 Δx²[step]    = sum(Δx.^2)
#                 Δu²[step]    = sum(Δu.^2)
#                 decrement!(stateᵢ,0,Δλ,Λdofgr)  
#                 decrement!(stateᵢ,0,Δx,Xdofgr)
#                 decrement!(stateᵢ,0,Δu,Udofgr)
#                 decrement!(stateᵢ,0,Δa,Adofgr)
#                 if ND
#             end    
#         end

#         for β∈λxu
#             for βder = 1:size(out.L1[β],1)
#                 for iβ ∈ finitediff(βder-1,nstep,step;transposed=true)
#                     βblk = 3*(step+iβ.Δs-1)+β
#                     addin!(bigasm,Lv,out.L1[β][βder],βblk,iβ.w/Δt)
#                 end
#             end
#         end
 

        
#         if saveiter
#             stateiter[iter]     = copy.(state) 
#         end
#         if all(Δλ².≤maxΔλ²)  && all(Δx².≤maxΔx²)  &&all(Δu².≤maxΔu²)  && Δa²≤maxΔa²  
#             verbose && @printf("\n    DirectXUA converged in %3d iterations.\n",iter)
#             verbose && @printf(  "    maxₜ(|ΔY|)=%7.1e  |ΔA|=%7.1e  \n",√(maximum(Δy²)),√(Δa²) )
#             verbose && @printf(  "    nel=%d, nvariables=%d, nstep=%d, niter=%d\n",getnele(model),nV,nstep,iter)
#             break#out of iter
#         end
#         iter<maxiter || muscadeerror(@sprintf("no convergence after %3d iterations. |ΔY|=%7.1e  |ΔA|=%7.1e \n",iter,√(maximum(Δy²)),√(Δa²)))
#     end # for iter
#     return
# end


