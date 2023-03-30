module TestElementCost

using Test,StaticArrays
using Muscade
include("SomeElements.jl")

model           = Model(:TestModel)
n1              = addnode!(model,𝕣[0,0,+100]) # turbine
n3              = addnode!(model,𝕣[])  # Anod for anchor

@once cost(out,key,X,U,A,t) = out[key.Fh]^2
el = ElementCost(model.nod;req=@request(Fh),cost,ElementType=AnchorLine, 
                 Δxₘtop=[5.,0,0], xₘbot=[250.,0], L=290., buoyancy=-5e3)
d  = doflist(typeof(el))
Nx,Nu,Na        = 3,0,2   
Nz              = 2Nx+Nu+Na     
iλ,ix,iu,ia     = Muscade.gradientpartition(Nx,Nx,Nu,Na) 
ΔZ              = δ{1,Nz,𝕣}()                 
ΔΛ,ΔX,ΔU,ΔA     = view(ΔZ,iλ),view(ΔZ,ix),view(ΔZ,iu),view(ΔZ,ia) 
Λ =  zeros(Nx)
X = (ones(Nx),)
U = (zeros(Nu),)
A =  zeros(Na)

L,χ,FB  = lagrangian(el, Λ+ΔΛ, (∂0(X)+ΔX,),(∂0(U)+ΔU,),A+ΔA, 0.,nothing,identity,nothing,(testall=true,))                 

@testset "ElementCost" begin
     @test d == (inod = (1, 1, 1, 2, 2), class = (:X, :X, :X, :A, :A), field = (:tx1, :tx2, :rx3, :ΔL, :Δbuoyancy))
     @test value{1}(L) ≈ 1.926851845351649e11
     @test ∂{1,8}(L) ≈ [-438861.1307445675,9278.602091074139,1.8715107899328927e6,-2.322235123921358e10,4.9097753633879846e8,9.903105530914653e10,-6.735986859485705e12,3.853703690703298e11]
end

end
