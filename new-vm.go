package main

import (
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/frelon/vmtest"
	"github.com/schollz/progressbar/v3"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

const (
	namespace    = "fleet-default"
	rawFile      = "sl-micro.x86_64.raw"
	qcow2File    = "sl-micro.x86_64.qcow2"
	firmwarePath = "/usr/share/qemu/ovmf-x86_64.bin"
	image        = "registry.opensuse.org/isv/rancher/elemental/dev/containers/suse/sl-micro/6.0/kvm-os-container:latest"

	group      = "elemental.cattle.io"
	version    = "v1beta1"
	apiVersion = group + "/" + version
)

func main() {
	var kubeconfig *string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}
	flag.Parse()

	if val, exist := os.LookupEnv("KUBECONFIG"); exist {
		kubeconfig = &val
	}

	ctx := context.Background()

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	dynClient, err := dynamic.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	seedRes := schema.GroupVersionResource{Group: group, Version: version, Resource: "seedimages"}
	client := dynClient.Resource(seedRes).Namespace(namespace)

	seedImgName := "fire-img"

	err = CreateSeedImage(ctx, client, seedImgName)
	if err != nil {
		fmt.Printf("Error creating seedimage: %s\n", err.Error())
		return
	}

	downloadUrl, err := WaitForImage(ctx, client, seedImgName)
	if err != nil {
		fmt.Printf("Error waiting for image: %s\n", err.Error())
		return
	}

	fmt.Printf("\nImage available at %s\n", downloadUrl)

	filename, err := DownloadImage(ctx, downloadUrl)
	if err != nil {
		fmt.Printf("Error downloading image: %s\n", err.Error())
		return
	}

	filename, err = GenerateQcow2(ctx, filename)
	if err != nil {
		fmt.Printf("Error downloading image: %s\n", err.Error())
		return
	}

	err = RunVM(filename)
	if err != nil {
		fmt.Printf("Error spawning VM: %s\n", err.Error())
		return
	}

	fmt.Printf("Done\n")
}

func getSeedResource(name, baseImage, registrationName string) *unstructured.Unstructured {
	return &unstructured.Unstructured{
		Object: map[string]interface{}{
			"apiVersion": apiVersion,
			"kind":       "SeedImage",
			"metadata": map[string]interface{}{
				"name":      name,
				"namespace": namespace,
			},
			"spec": map[string]interface{}{
				"cleanupAfterMinutes": 0,
				"size":                "10Gi",
				"type":                "raw",
				"baseImage":           baseImage,
				"registrationRef": map[string]interface{}{
					"apiVersion": apiVersion,
					"kind":       "MachineRegistration",
					"name":       registrationName,
					"namespace":  namespace,
				},
				"cloud-config": map[string]interface{}{
					"users": []map[string]interface{}{
						{
							"name":   "root",
							"passwd": "linux",
						},
					},
				},
			},
		},
	}
}

func CreateSeedImage(ctx context.Context, client dynamic.ResourceInterface, name string) error {
	fmt.Printf("Creating CRD...")

	seedImg := getSeedResource(name, image, "my-nodes")

	_, err := client.Get(ctx, name, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		_, err = client.Create(ctx, seedImg, metav1.CreateOptions{})

		if err == nil {
			fmt.Printf(" Done!\n")
		}

		return err
	}

	fmt.Printf("\nSeedImage already exists, skipping")

	return nil
}

func WaitForImage(ctx context.Context, client dynamic.ResourceInterface, name string) (string, error) {
	bar := progressbar.NewOptions(-1, progressbar.OptionSetDescription("Waiting for image build..."))
	var downloadUrl string

	for i := 0; i < 10*60; i++ {
		data, err := client.Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			panic(err)
		}

		if stat, ok := data.Object["status"]; ok {
			status := stat.(map[string]interface{})
			if status["downloadURL"] != nil {
				downloadUrl = status["downloadURL"].(string)
				return downloadUrl, nil
			}
		}

		bar.Add(1)
		time.Sleep(1 * time.Second)
	}

	return "", errors.New("Timeout")
}

func DownloadImage(ctx context.Context, downloadUrl string) (string, error) {
	if f, err := os.Stat(rawFile); err == nil && f.Size() != 0 {
		fmt.Printf("File already downloaded, skipping\n")
		return rawFile, nil
	}

	req, err := http.NewRequestWithContext(ctx, "GET", downloadUrl, nil)
	if err != nil {
		fmt.Printf("Error creating GET: %s\n", err.Error())
		return "", err
	}

	// TODO add insecure flag
	customTransport := http.DefaultTransport.(*http.Transport).Clone()
	customTransport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
	httpClient := &http.Client{Transport: customTransport}

	resp, err := httpClient.Do(req)
	if err != nil {
		fmt.Printf("Error sending request: %s\n", err.Error())
		return "", err
	}

	defer resp.Body.Close()

	f, _ := os.OpenFile(rawFile, os.O_CREATE|os.O_WRONLY, 0644)
	defer f.Close()

	bar := progressbar.DefaultBytes(
		resp.ContentLength,
		"Downloading raw image",
	)
	io.Copy(io.MultiWriter(f, bar), resp.Body)

	return rawFile, nil
}

func GenerateQcow2(ctx context.Context, filename string) (string, error) {
	cmd := exec.CommandContext(ctx, "qemu-img", "convert", "-O", "qcow2", filename, qcow2File)
	if err := cmd.Run(); err != nil {
		fmt.Printf("Error converting to qcow2: %s\n", err.Error())
		return "", err
	}

	cmd = exec.CommandContext(ctx, "qemu-img", "resize", qcow2File, "30G")
	if err := cmd.Run(); err != nil {
		fmt.Printf("Error resizing qcow2: %s\n", err.Error())
		return "", err
	}

	return qcow2File, nil
}

func RunVM(filename string) error {
	fmt.Printf("Spawning VM from %s\n", filename)

	// -device virtio-net-pci,netdev=user0,mac=XX:XX:XX:XX:XX:XX \
	// -netdev bridge,id=user0,br=vbr0

	opts := vmtest.QemuOptions{
		OperatingSystem: vmtest.OS_LINUX,
		Params: []string{
			"-enable-kvm",
			"-cpu", "host",
			"-m", "4G",
			"-bios", firmwarePath,
			"-device", "virtio-net-pci,netdev=user0,mac=52:54:00:34:07:70",
			"-netdev", "bridge,id=user0,br=vbr0",
		},
		Disks: []vmtest.QemuDisk{
			{Path: filename, Format: "qcow2"},
		},
		Timeout: 20 * time.Second,
		Verbose: true,
	}
	// Run QEMU instance
	qemu, err := vmtest.NewQemu(&opts)
	if err != nil {
		return err
	}

	fmt.Printf("Started VM, exit with Ctrl+C\n")

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	go func() {
		for _ = range c {
			fmt.Printf("Ctrl+C received, killing qemu instance.\n")
			qemu.Kill()
			os.Exit(0)
		}
	}()

	for {
		time.Sleep(10 * time.Second)
	}
}
