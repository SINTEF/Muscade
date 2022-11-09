module TestAssemble

using Test,StaticArrays,SparseArrays
using Muscade
using Muscade.ElTest

include("SomeElements.jl")

### Turbine
sea(t,x) = SVector(1.,0.)
sky(t,x) = SVector(0.,1.)
turbine  = Turbine(SVector(0.,0.),-10., 2.,sea, 3.,sky)
δX       = @SVector [1.,1.]
X        = @SVector [1.,2.]
U        = @SVector 𝕣[]
A        = @SVector [0.,0.]  # [Δseadrag,Δskydrag]


L,Lδx,Lx,Lu,La   = Muscade.gradient(turbine,δX,[X],[U],A, 0.,0.,())

@testset "Turbine gradient" begin
    @test Lδx           ≈ [2, 3]
    @test Lx            ≈ [0, 0]
    @test length(Lu)    == 0
    @test La            ≈ [1, 1]
end

Lδx,Lx,Lu,La   = test_static_element(turbine;δX,X,U,A,verbose=false)

@testset "test_static_element" begin
    @test Lδx           ≈ [2, 3]
    @test Lx            ≈ [0, 0]
    @test length(Lu)    == 0
    @test La            ≈ [1, 1]
end

# ###  AnchorLine

anchorline      = AnchorLine(SVector(0.,0.,100.), SVector(0,2.,0), SVector(94.,0.), 170., -1.)

δX       = @SVector [1.,1.,1.]
X        = @SVector [0.,0.,0.]
U        = @SVector 𝕣[]
A        = @SVector [0.,0.]  # [Δseadrag,Δskydrag]
L,Lδx,Lx,Lu,La   = Muscade.gradient(anchorline,δX,[X],[U],A, 0.,0.,())
@testset "anchorline1" begin
    @test Lδx           ≈ [-12.25628901693551, 0.2607721067433087, 24.51257803387102]
    @test Lx            ≈ [-0.91509745608786, 0.14708204066349, 1.3086506986891027]
    @test length(Lu)    == 0
    @test La            ≈ [-0.9180190940689051, -12.517061123678818]
end

model           = Model(:TestModel)
n1              = addnode!(model,𝕣[0,0,+100])
n2              = addnode!(model,𝕣[])
n3              = addnode!(model,𝕣[])
sea(t,x)        = SVector(1.,0.)
sky(t,x)        = SVector(0.,1.)
e1              = addelement!(model,Turbine   ,[n1,n2], seadrag=2., sea=sea, skydrag=3., sky=sky)
e2              = addelement!(model,AnchorLine,[n1,n3], Δxₘtop=SVector(5.,0.,0), xₘbot=SVector(150.,0.), L=180., buoyancy=-1e3)
setscale!(model;scale=(X=(tx1=1.,tx2=1.,rx3=2.),A=(Δseadrag=3.,Δskydrag=4.,ΔL=5)),Λscale=2)  # scale = (X=(tx=10,rx=1),A=(drag=3.))

@testset "Disassembler" begin
    @test  model.disassembler[1][1].index.X == [1,2]
    @test  model.disassembler[1][1].index.U == []
    @test  model.disassembler[1][1].index.A == [1,2]
    @test  model.disassembler[2][1].index.X == [1,2,3]
    @test  model.disassembler[2][1].index.U == []
    @test  model.disassembler[2][1].index.A == [3,4]
    @test  model.disassembler[1][1].scale.X ≈  [1,1]
    @test  model.disassembler[1][1].scale.U ≈  𝕫[]
    @test  model.disassembler[1][1].scale.A ≈  [3,4]
    @test  model.disassembler[2][1].scale.X ≈  [1,1,2]
    @test  model.disassembler[2][1].scale.U ≈  𝕫[]
    @test  model.disassembler[2][1].scale.A ≈  [5,1]
end

asm = Muscade.ASMstaticX(model)
nX  = Muscade.getndof(model,:X)
nU  = Muscade.getndof(model,:U)
nA  = Muscade.getndof(model,:A)
Λ   =  zeros(nX)
X   = (zeros(nX),)
U   = (zeros(nU),)
A   =  zeros(nA)
t   = 0.
ε   = 0.
dbg = ()
Muscade.assemble!(asm,model,Λ,X,U,A, t,ε,dbg)

@testset "DASMstaticX" begin
    @test  asm.R ≈ [-152126.71199858442, 3.0, 0.0]
    @test  asm.K ≈ sparse([1, 2, 3, 2, 3], [1, 2, 2, 3, 3], [10323.069597975566, 1049.1635310247202, 5245.817655123601, 5245.8176551236, 786872.6482685402], 3, 3)
end

end
